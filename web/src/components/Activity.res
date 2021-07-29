// Copyright (C) 2021 Monocle authors
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The activity view
//
open Prelude

module CChangesLifeCycleStats = {
  @react.component @module("./changes_lifecycle.jsx")
  external make: (
    ~store: Store.t,
    ~data: SearchTypes.lifecycle_stats,
    ~created_histo: array<SearchTypes.histo>,
    ~updated_histo: array<SearchTypes.histo>,
    ~merged_histo: array<SearchTypes.histo>,
    ~abandoned_histo: array<SearchTypes.histo>,
  ) => React.element = "default"
}

module ChangesLifeCycleStats = {
  @react.component
  let make = (~store: Store.t) => {
    let (state, _) = store
    let request = Store.mkSearchRequest(state, SearchTypes.Query_changes_lifecycle_stats)

    {
      switch useAutoGetOn(() => WebApi.Search.query(request), state.query) {
      | None => <Spinner />
      | Some(Error(title)) => <Alert variant=#Danger title />
      | Some(Ok(SearchTypes.Error(err))) =>
        <Alert
          title={err.message ++ " at " ++ string_of_int(Int32.to_int(err.position))} variant=#Danger
        />
      | Some(Ok(SearchTypes.Lifecycle_stats(data))) =>
        <CChangesLifeCycleStats
          store
          data
          created_histo={data.created_histo->Belt.List.toArray}
          updated_histo={data.updated_histo->Belt.List.toArray}
          merged_histo={data.merged_histo->Belt.List.toArray}
          abandoned_histo={data.abandoned_histo->Belt.List.toArray}
        />
      | Some(Ok(_)) => /* Response does not match request */ React.null
      }
    }
  }
}

module CChangesReviewStats = {
  @react.component @module("./changes_review.jsx")
  external make: (
    ~data: SearchTypes.review_stats,
    ~comment_histo: array<SearchTypes.histo>,
    ~review_histo: array<SearchTypes.histo>,
  ) => React.element = "ChangesReviewStats"
}

module ChangesReviewStats = {
  @react.component
  let make = (~store: Store.t) => {
    let (state, _) = store
    let request = Store.mkSearchRequest(state, SearchTypes.Query_changes_review_stats)

    {
      switch useAutoGetOn(() => WebApi.Search.query(request), state.query) {
      | None => <Spinner />
      | Some(Error(title)) => <Alert variant=#Danger title />
      | Some(Ok(SearchTypes.Error(err))) =>
        <Alert
          title={err.message ++ " at " ++ string_of_int(Int32.to_int(err.position))} variant=#Danger
        />
      | Some(Ok(SearchTypes.Review_stats(data))) =>
        <CChangesReviewStats
          data
          comment_histo={data.comment_histo->Belt.List.toArray}
          review_histo={data.review_histo->Belt.List.toArray}
        />
      | Some(Ok(_)) => /* Response does not match request */ React.null
      }
    }
  }
}

module DurationComplexicityGraph = {
  @react.component @module("./duration_complexity_graph.jsx")
  external make: (~data: array<SearchTypes.change>, ~onClick: string => unit) => React.element =
    "default"
}

module ChangesMergedDuration = {
  @react.component
  let make = (~store: Store.t) => {
    let (state, _) = store
    let query = addQuery(state.query, "state:merged")
    let request = {
      ...Store.mkSearchRequest(state, SearchTypes.Query_change),
      query: query,
    }
    let onClick = changeId => {
      let link = "/" ++ state.index ++ "/change/" ++ changeId
      link->RescriptReactRouter.push
    }
    switch useAutoGetOn(() => WebApi.Search.query(request), query) {
    | None => <Spinner />
    | Some(Ok(SearchTypes.Changes(items))) =>
      <DurationComplexicityGraph data={items.changes->Belt.List.toArray} onClick />
    | _ => React.null
    }
  }
}

module CAuthorsHistoStats = {
  @react.component @module("./authors_histo.jsx")
  external make: (
    ~change_authors: int32,
    ~comment_authors: int32,
    ~review_authors: int32,
    ~change_histo: array<SearchTypes.histo>,
    ~comment_histo: array<SearchTypes.histo>,
    ~review_histo: array<SearchTypes.histo>,
  ) => React.element = "CAuthorsHistoStats"
}

module AuthorHistoStats = {
  @react.component
  let make = (~store: Store.t) => {
    let (state, _) = store
    let request = Store.mkSearchRequest(state, SearchTypes.Query_active_authors_stats)

    {
      switch useAutoGetOn(() => WebApi.Search.query(request), state.query) {
      | None => <Spinner />
      | Some(Error(title)) => <Alert variant=#Danger title />
      | Some(Ok(SearchTypes.Error(err))) =>
        <Alert
          title={err.message ++ " at " ++ string_of_int(Int32.to_int(err.position))} variant=#Danger
        />
      | Some(Ok(SearchTypes.Activity_stats(data))) =>
        <CAuthorsHistoStats
          change_authors={data.change_authors}
          comment_authors={data.comment_authors}
          review_authors={data.review_authors}
          change_histo={data.changes_histo->Belt.List.toArray}
          comment_histo={data.comments_histo->Belt.List.toArray}
          review_histo={data.reviews_histo->Belt.List.toArray}
        />
      | Some(Ok(_)) => /* Response does not match request */ React.null
      }
    }
  }
}

@react.component
let make = (~store: Store.t) => {
  <div className="container">
    <MStack>
      <MStackItem> <ChangesLifeCycleStats store /> </MStackItem>
      <MStackItem> <ChangesReviewStats store /> </MStackItem>
      <MStackItem> <ChangesMergedDuration store /> </MStackItem>
      <MStackItem> <AuthorHistoStats store /> </MStackItem>
    </MStack>
  </div>
}

let default = make
