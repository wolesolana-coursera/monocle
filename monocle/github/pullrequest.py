# MIT License
# Copyright (c) 2019 Fabien Boucher

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


import logging
import requests
from datetime import datetime
from time import sleep


class PRsFetcher(object):

    log = logging.getLogger("monocle.PRsFetcher")

    def __init__(self, gql, bulk_size=25):
        self.gql = gql
        self.size = bulk_size
        self.pr_query = '''
          id
          updatedAt
          createdAt
          mergedAt
          closedAt
          title
          state
          number
          mergeable
          labels (first: 100){
            edges {
              node {
                name
              }
            }
          }
          assignees (first: 100){
            edges {
              node {
                login
              }
            }
          }
          comments (first: 100){
            edges {
              node {
                id
                createdAt
                author {
                  login
                }
              }
            }
          }
          commits (first: 100){
            edges {
              node {
                commit {
                  oid
                  authoredDate
                  committedDate
                  author {
                    user {
                      login
                    }
                  }
                  committer {
                    user {
                      login
                    }
                  }
                }
              }
            }
          }
          timelineItems (first: 100 itemTypes: [CLOSED_EVENT, ASSIGNED_EVENT, CONVERTED_NOTE_TO_ISSUE_EVENT, LABELED_EVENT, PULL_REQUEST_REVIEW]) {
            edges {
              node {
                __typename
                ... on ClosedEvent {
                  id
                  createdAt
                  actor {
                    login
                  }
                }
                ... on AssignedEvent {
                  id
                  createdAt
                  actor {
                    login
                  }
                }
                ... on ConvertedNoteToIssueEvent {
                  id
                  createdAt
                  actor {
                    login
                  }
                }
                ... on LabeledEvent {
                  id
                  createdAt
                  actor {
                    login
                  }
                }
                ... on PullRequestReview {
                  id
                  createdAt
                  author {
                    login
                  }
                }
              }
            }
          }
          author {
            login
          }
          mergedBy {
            login
          }
          repository {
            owner {
              login
            }
            name
          }
        '''

    def _getPage(self, kwargs, prs):
        # Note: usage of the default sort on created field because
        # sort on the updated field does not return well ordered PRs
        qdata = '''{
          search(query: "org:%(org)s is:pr sort:created updated:>%(updated_since)s created:<%(created_before)s" type: ISSUE first: %(size)s %(after)s) {
            issueCount
            pageInfo {
              hasNextPage endCursor
            }
            edges {
              node {
                ... on PullRequest {
                    %(pr_query)s
                }
              }
            }
          }
        }'''
        data = self.gql.query(qdata % kwargs)
        if not kwargs['total_prs_count']:
            kwargs['total_prs_count'] = data['data']['search']['issueCount']
            self.log.info("Total PRs to fetch: %s" % kwargs['total_prs_count'])
        for pr in data['data']['search']['edges']:
            prs.append(pr['node'])
        pageInfo = data['data']['search']['pageInfo']
        if pageInfo['hasNextPage']:
            kwargs['after'] = 'after: "%s"' % pageInfo['endCursor']
            return True
        else:
            return False

    def get(self, org, updated_since):
        prs = []
        kwargs = {
            'pr_query': self.pr_query,
            'org': org,
            'updated_since': updated_since,
            'after': '',
            'created_before': datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ"),
            'total_prs_count': 0,
            'size': self.size
        }

        while True:
            self.log.info('Running request %s' % dict(
                [(k, v) for k, v in kwargs.items() if k != 'pr_query']))
            try:
                hnp = self._getPage(kwargs, prs)
            except requests.exceptions.ConnectionError:
                self.log.exception(
                    "Error connecting to the Github API - retrying in 5s ...")
                sleep(5)
                continue
            self.log.info("%s PRs fetched" % len(prs))
            if not hnp:
                if (len(prs) < kwargs['total_prs_count'] and
                        len(prs) % self.size == 0):
                    kwargs['created_before'] = prs[-1]['createdAt']
                    kwargs['after'] = ''
                    continue
                break
        return prs

    def get_pr(self, org, repository, number):
        qdata = '''{
          repository(owner: "%(org)s", name:"%(repository)s") {
            pullRequest(number: %(number)s) {
              %(pr_query)s
            }
          }
        }
        '''
        kwargs = {
            'pr_query': self.pr_query,
            'org': org,
            'repository': repository,
            'number': number
        }
        return self.gql.query(qdata % kwargs)

    def extract_objects(self, prs):
        def timedelta(start, end):
            format = "%Y-%m-%dT%H:%M:%SZ"
            start = datetime.strptime(start, format)
            end = datetime.strptime(end, format)
            return int((start - end).total_seconds())

        def extract_pr_objects(pr):
            objects = []
            change = {}
            change['type'] = 'PullRequest'
            change['id'] = pr['id']
            change['number'] = pr['number']
            change['repository_owner'] = pr['repository']['owner']['login']
            change['repository'] = pr['repository']['name']
            change['author'] = pr['author']['login']
            change['title'] = pr['title']
            if pr['mergedBy']:
                change['merged_by'] = pr['mergedBy']['login']
            else:
                change['merged_by'] = None
            change['updated_at'] = pr['updatedAt']
            change['created_at'] = pr['createdAt']
            change['merged_at'] = pr['mergedAt']
            change['closed_at'] = pr['closedAt']
            change['state'] = pr['state']
            if pr['state'] in ('CLOSED', 'MERGED'):
                change['duration'] = timedelta(
                  change['closed_at'], change['created_at'])
            change['mergeable'] = pr['mergeable']
            change['labels'] = tuple(map(
                lambda n: n['node']['name'], pr['labels']['edges']))
            change['assignees'] = tuple(map(
                lambda n: n['node']['login'], pr['assignees']['edges']))
            objects.append(change)
            objects.append({
                'type': 'PRCreatedEvent',
                'id': 'CE' + pr['id'],
                'created_at': pr['createdAt'],
                'author': pr['author']['login'],
                'repository_owner': pr['repository']['owner']['login'],
                'repository': pr['repository']['name'],
                'number': pr['number'],
            })
            for comment in pr['comments']['edges']:
                _comment = comment['node']
                objects.append(
                    {
                        'type': 'PRCommentedEvent',
                        'id': _comment['id'],
                        'created_at': _comment['createdAt'],
                        'author': _comment['author']['login'],
                        'repository_owner': pr['repository']['owner']['login'],
                        'repository': pr['repository']['name'],
                        'number': pr['number'],
                        'on_author': pr['author']['login'],
                    }
                )
            for commit in pr['commits']['edges']:
                _commit = commit['node']
                obj = {
                    'type': 'PRCommitCreatedEvent',
                    'id': _commit['commit']['oid'],
                    'authored_at': _commit['commit']['authoredDate'],
                    'committed_at': _commit['commit']['committedDate'],
                    'repository_owner': pr['repository']['owner']['login'],
                    'repository': pr['repository']['name'],
                    'number': pr['number'],
                }
                if _commit['commit']['author']['user']:
                    obj['author'] = _commit[
                      'commit']['author']['user']['login']
                else:
                    obj['author'] = None
                if _commit['commit']['committer']['user']:
                    obj['committer'] = _commit[
                      'commit']['committer']['user']['login']
                else:
                    obj['committer'] = None
                objects.append(obj)
            for timelineitem in pr['timelineItems']['edges']:
                _timelineitem = timelineitem['node']
                obj = {
                    'type': 'PR' + _timelineitem['__typename'],
                    'id': _timelineitem['id'],
                    'created_at': _timelineitem['createdAt'],
                    'author': (
                        _timelineitem.get('actor', {}).get('login') or
                        _timelineitem.get('author', {}).get('login')
                    ),
                    'repository_owner': pr['repository']['owner']['login'],
                    'repository': pr['repository']['name'],
                    'number': pr['number'],
                    'on_author': pr['author']['login'],
                }
                objects.append(obj)
            return objects

        objects = []
        for pr in prs:
            try:
                objects.extend(extract_pr_objects(pr))
            except Exception:
                self.log.exception("Unable to extract PR data: %s" % pr)
        return objects
