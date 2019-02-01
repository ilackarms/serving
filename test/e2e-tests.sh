#!/usr/bin/env bash

# Copyright 2018 The Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script runs the end-to-end tests against Knative Serving built from source.
# It is started by prow for each PR. For convenience, it can also be executed manually.

# If you already have the *_OVERRIDE environment variables set, call
# this script with the --run-tests arguments and it will start knative in
# the cluster and run the tests.

# Calling this script without arguments will create a new cluster in
# project $PROJECT_ID, start knative in it, run the tests and delete the
# cluster.

source $(dirname $0)/e2e-common.sh

# Helper functions.
function dump_app_logs() {
  echo ">>> Knative Serving $1 logs:"
  for pod in $(get_app_pods "$1" knative-serving)
  do
    echo ">>> Pod: $pod"
    kubectl -n knative-serving logs "$pod" -c "$1"
  done
}

function dump_extra_cluster_state() {
  echo ">>> Routes:"
  kubectl get routes -o yaml --all-namespaces
  echo ">>> Configurations:"
  kubectl get configurations -o yaml --all-namespaces
  echo ">>> Revisions:"
  kubectl get revisions -o yaml --all-namespaces

  dump_app_logs controller
  dump_app_logs webhook
  dump_app_logs autoscaler
  dump_app_logs activator
}

# Script entry point.

initialize $@

header "Setting up environment"

if [[ "${RUN_GLOO_TESTS}" -eq "1" ]]; then
  echo "Running e2e tests using Gloo in place of Istio"
  install_knative_serving_gloo_version || fail_test "Knative Serving installation failed"
  export GATEWAY_OVERRIDE="clusteringress-proxy"
  export GATEWAY_NAMESPACE_OVERRIDE="gloo-system"
else
  install_knative_serving || fail_test "Knative Serving installation failed"
fi

publish_test_images || fail_test "one or more test images weren't published"

# Run the tests
header "Running tests"
failed=0

# Run conformance tests, but don't exit if it fails.
go_test_e2e -timeout=10m ./test/conformance || failed=1

# So that we can also identify failing E2E tests.
go_test_e2e -timeout=20m ./test/e2e || failed=1

# Require that both set of tests succeeded.
(( failed )) && fail_test

success
