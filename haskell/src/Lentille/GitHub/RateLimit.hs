{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}

module Lentille.GitHub.RateLimit where

import Data.Morpheus.Client
import Lentille
  ( Log (Log),
    LogAuthor (Macroscope),
    LogEvent (LogRaw),
    MonadGraphQLE,
    MonadLog,
    MonadRetry (genericRetry),
    MonadTime (mThreadDelay),
    mLog,
  )
import Lentille.GraphQL
import Monocle.Prelude
import Network.HTTP.Client (Response, responseBody, responseStatus)
import Network.HTTP.Types (Status, badGateway502, forbidden403)

newtype DateTime = DateTime Text deriving (Show, Eq, EncodeScalar, DecodeScalar)

defineByDocumentFile
  ghSchemaLocation
  [gql|
    query GetRateLimit  {
      rateLimit {
        used
        remaining
        resetAt
      }
    }
  |]

transformResponse :: GetRateLimit -> RateLimit
transformResponse = \case
  GetRateLimit
    ( Just
        (RateLimitRateLimit used remaining (DateTime resetAt'))
      ) -> case parseDateValue $ from resetAt' of
      Just resetAt -> RateLimit {..}
      Nothing -> error $ "Unable to parse the resetAt date string: " <> resetAt'
  respOther -> error ("Invalid response: " <> show respOther)

getRateLimit :: (MonadGraphQLE m) => GraphClient -> m RateLimit
getRateLimit client = do
  (respE, reqLog) <- gRetry (const $ retryCheck Macroscope) remoteCallDelay getLimit
  case respE of
    Left err -> handleReqLog err reqLog
    Right resp -> pure $ transformResponse resp
  where
    gRetry = genericRetry Macroscope "Faulty response when fetching rateLimit - retrying request"
    getLimit _ = fetchWithLog (doGraphRequest client) ()

data GHRequestIssue = GHRequestTimeout | GHRequestSecondaryRateLimit | GHRequestUnmatchedIssue

retryCheck :: MonadLog m => LogAuthor -> RetryCheck m a
retryCheck author respI = do
  issueType <- case snd respI of
    [reqlog] -> checkResp $ snd reqlog
    _other -> error "Unexpected empty reqlog"
  case issueType of
    GHRequestTimeout -> do
      mLog $ Log author $ LogRaw "Server side timeout error. Will retry with lower query depth ..."
      pure True
    GHRequestSecondaryRateLimit -> do
      mLog $ Log author $ LogRaw "Secondary rate limit error. Will retry after 60 seconds ..."
      mThreadDelay $ 60 * 1_000_000
      pure True
    GHRequestUnmatchedIssue -> pure False
  where
    checkResp :: MonadLog m => Response LByteString -> m GHRequestIssue
    checkResp resp = do
      let status = responseStatus resp
          body = decodeUtf8 $ responseBody resp
      if isTimeoutError status body
        then pure GHRequestTimeout
        else
          if isSecondaryRateLimitError status body
            then pure GHRequestSecondaryRateLimit
            else pure GHRequestUnmatchedIssue
    isTimeoutError :: Status -> Text -> Bool
    isTimeoutError status body =
      let msg = "Something went wrong while executing your query. This may be the result of a timeout"
       in status == badGateway502 && inText msg body
    -- https://docs.github.com/en/rest/overview/resources-in-the-rest-api#secondary-rate-limits
    isSecondaryRateLimitError :: Status -> Text -> Bool
    isSecondaryRateLimitError status body =
      let msg = "You have exceeded a secondary rate limit."
       in status == forbidden403 && inText msg body
