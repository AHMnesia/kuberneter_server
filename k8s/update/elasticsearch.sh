#!/bin/bash

# Check for required commands
for cmd in kubectl curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' not found in PATH. Install $cmd before running this script." >&2
        exit 1
    fi
done

namespace_elasticsearch=${namespace_elasticsearch:-elasticsearch}
elastic_user=${elastic_user:-elastic}
cluster_soak_seconds=${cluster_soak_seconds:-120}



main_menu() {
    echo -e "\nSelect operation:"
    echo "1. Restart Elasticsearch"
    echo "2. Data Operations"
    read -p "Enter choice (1 or 2): " choice
    if [ "$choice" = "1" ]; then
        restart_elasticsearch
    elif [ "$choice" = "2" ]; then
        data_operations
    else
        echo "Invalid choice. Please enter 1 or 2." >&2
        exit 1
    fi
}

restart_elasticsearch() {
    echo "Proceeding with Elasticsearch restart..."
    script_dir=$(dirname "$0")
    root=$(dirname "$script_dir")
    es_dir="$root/elasticsearch"
    echo "Applying latest Elasticsearch manifests (if present) from: $es_dir"
    files=("deployment.yaml" "service.yaml" "statefulset.yaml")
    for f in "${files[@]}"; do
        f_path="$es_dir/$f"
        if [ -f "$f_path" ]; then
            echo "  Applying $f_path"
            kubectl apply -f "$f_path" -n "$namespace_elasticsearch"
            if [ $? -ne 0 ]; then
                echo "  Warning: kubectl apply returned non-zero for $f_path" >&2
            fi
        fi
    done
    while true; do
        pod_names=($(kubectl get pods -n "$namespace_elasticsearch" -l app=elasticsearch -o jsonpath="{.items[*].metadata.name}"))
        if [ ${#pod_names[@]} -eq 0 ]; then
            echo "No pods found with label app=elasticsearch in namespace $namespace_elasticsearch" >&2
            break
        fi
        echo -e "\nList of Elasticsearch pods:"
        pod_index=0
        for pod_name in "${pod_names[@]}"; do
            ready_status="NotReady"
            pod_ready=$(kubectl get pod "$pod_name" -n "$namespace_elasticsearch" -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
            if [ "$pod_ready" = "True" ]; then
                ready_status="Ready"
            fi
            echo "$pod_index. $pod_name : $ready_status"
            pod_index=$((pod_index + 1))
        done
        read -p "Enter pod number to restart (0-$((pod_index-1)), or blank to exit): " selected_index
        if [ -z "$selected_index" ]; then
            echo "Exiting restart mode."
            break
        fi
        if ! [[ $selected_index =~ ^[0-9]+$ ]] || [ "$selected_index" -lt 0 ] || [ "$selected_index" -ge "$pod_index" ]; then
            echo "Invalid pod number: $selected_index" >&2
            continue
        fi
        selected_pod="${pod_names[$selected_index]}"
        echo "Deleting pod $selected_pod (grace 30s) to trigger replacement..."
        kubectl delete pod "$selected_pod" -n "$namespace_elasticsearch" --grace-period=30 --wait=false
        timeout=600
        elapsed=0
        while [ $elapsed -lt $timeout ]; do
            sleep 5
            elapsed=$((elapsed + 5))
            pod_ready=$(kubectl get pod "$selected_pod" -n "$namespace_elasticsearch" -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
            if [ "$pod_ready" = "True" ]; then
                echo "Pod $selected_pod successfully restarted and ready."
                break
            fi
            echo "  Waiting for pod $selected_pod to be ready... ($elapsed/$timeout seconds)"
        done
        if [ $elapsed -ge $timeout ]; then
            echo "Timeout waiting for pod $selected_pod to become ready" >&2
        fi
        # Loop to allow next pod restart or exit
    done
}

data_operations() {
    echo "Data Operations - Import data into Elasticsearch from elasticsearch/data/ directory"
    if [ -z "$elastic_user" ]; then
        read -p "Enter Elasticsearch username (default: elastic): " elastic_user
        if [ -z "$elastic_user" ]; then
            elastic_user='elastic'
        fi
    fi
    if [ -z "$elastic_password" ]; then
        read -s -p "Enter Elasticsearch password: " elastic_password
        echo ""
    fi
    if [ -z "$elastic_password" ]; then
        echo "Elasticsearch password is required for data operations." >&2
        exit 1
    fi
    echo "Testing Elasticsearch connection and credentials..."
    set +e
    test_response=$(curl -k -s -f -u "${elastic_user}:${elastic_password}" "https://search.suma-honda.local/_cluster/health" 2>/dev/null)
    curl_exit=$?
    set -e
    if [ $curl_exit -ne 0 ]; then
        echo "Authentication failed. Please check your Elasticsearch username and password." >&2
        exit 1
    fi
    if echo "$test_response" | grep -q '"error"'; then
        error_reason=$(echo "$test_response" | grep '"reason"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        echo "Authentication failed: $error_reason" >&2
        exit 1
    fi
    status=$(echo "$test_response" | grep '"status"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    if [ "$status" != "yellow" ] && [ "$status" != "green" ] && [ "$status" != "red" ]; then
        echo "Invalid cluster health response. Expected status yellow/green/red, got: $status" >&2
        exit 1
    fi
    echo "Elasticsearch connection successful. Cluster status: $status"
    # Match PowerShell reference: c:/docker/elasticsearch/data
    data_dir="/c/docker/elasticsearch/data"
    if [ ! -d "$data_dir" ]; then
        echo "Data directory not found: $data_dir" >&2
        exit 1
    fi
    data_files=($(find "$data_dir" -maxdepth 1 -type f \( -name "*.json" -o -name "*.csv" \) | sort))
    if [ ${#data_files[@]} -eq 0 ]; then
        echo "No .json or .csv files found in $data_dir" >&2
        echo "Please place your data files (.json or .csv) in the elasticsearch/data/ directory." >&2
        exit 1
    fi
    echo -e "\nAvailable data files:"
    for i in "${!data_files[@]}"; do
        ext="${data_files[$i]##*.}"
        file_type="JSON"
        if [ "$ext" = "csv" ]; then
            file_type="CSV"
        fi
        echo "$((i+1)). $(basename "${data_files[$i]}") ($file_type)"
    done
    read -p "Enter file number to import (1-${#data_files[@]}): " selected_index
    if ! [[ $selected_index =~ ^[0-9]+$ ]] || [ "$selected_index" -lt 1 ] || [ "$selected_index" -gt ${#data_files[@]} ]; then
        echo "Invalid file number: $selected_index" >&2
        exit 1
    fi
    selected_file="${data_files[$((selected_index-1))]}"
    file_path="$selected_file"
    ext="${selected_file##*.}"
    file_type="JSON"
    if [ "$ext" = "csv" ]; then
        file_type="CSV"
    fi
    echo "Selected file: $(basename "$selected_file") ($file_type)"
    base_name=$(basename "$selected_file")
    if [ "$base_name" = "createIndexProduk.json" ] || [ "$base_name" = "createindex.json" ] || [ "$base_name" = "createIndexCategori.json" ]; then
        echo "Creating Elasticsearch index from configuration file..."
        index_name=$(grep '"index_name"' "$file_path" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        if [ -z "$index_name" ]; then
            echo "Index name not found in configuration file." >&2
            exit 1
        fi
        echo "Creating index: $index_name"
        es_config=$(grep -v '"index_name"' "$file_path")
        temp_file=$(mktemp)
        echo "$es_config" > "$temp_file"
        create_response=$(curl -k -s -f -X PUT -u "${elastic_user}:${elastic_password}" "https://search.suma-honda.local/$index_name" -H "Content-Type: application/json" -d "@$temp_file" 2>/dev/null)
        rm "$temp_file"
        if [ $? -eq 0 ]; then
            if echo "$create_response" | grep -q '"acknowledged": *true'; then
                echo "Index $index_name created successfully."
                exit 0
            else
                echo "Failed to create index. Response: $create_response" >&2
                exit 1
            fi
        else
            echo "curl command failed with exit code $?" >&2
            exit 1
        fi
    else
        first_line=$(head -1 "$file_path")
        if echo "$first_line" | grep -q '"index"' && echo "$first_line" | grep -q '"_index"'; then
            echo "File contains bulk API format with index information. Importing directly..."
            bulk_index_name=$(echo "$first_line" | grep '"_index"' | sed 's/.*_index": *"\([^"]*\)".*/\1/')
            echo "Detected index name from bulk data: $bulk_index_name"
            index_check_response=$(curl -k -s -u "${elastic_user}:${elastic_password}" "https://search.suma-honda.local/$bulk_index_name" 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "Index $bulk_index_name does not exist. Please create the index first." >&2
                exit 1
            fi
            if echo "$index_check_response" | grep -q '"error"'; then
                echo "Index $bulk_index_name does not exist. Please create the index first." >&2
                exit 1
            fi
            index_name="$bulk_index_name"
        else
            read -p "Enter Elasticsearch index name (example: my_index): " index_name
        fi
        import_data "$file_path" "$file_type" "$index_name" "$elastic_user" "$elastic_password" "$namespace_elasticsearch"
    fi
}

import_data() {
    file_path=$1
    file_type=$2
    index_name=$3
    elastic_user=$4
    elastic_password=$5
    namespace=$6
    echo "Connecting to remote Elasticsearch at search.suma-honda.local..."
    echo "Importing $file_type data from $file_path to index $index_name..."
    if [ "$file_type" = "CSV" ] && command -v elasticsearch-loader >/dev/null 2>&1; then
        elasticsearch-loader --es-host https://search.suma-honda.local --user "$elastic_user" --password "$elastic_password" --index "$index_name" --type _doc csv "$file_path"
        if [ $? -ne 0 ]; then
            echo "elasticsearch-loader failed with exit code $?" >&2
            exit 1
        fi
    else
        echo "Using curl method for bulk import..."
        bulk_response=$(curl -k -s -u "${elastic_user}:${elastic_password}" -X POST "https://search.suma-honda.local/_bulk" -H "Content-Type: application/x-ndjson" --data-binary "@$file_path" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "curl command failed with exit code $?" >&2
            exit 1
        fi
        if echo "$bulk_response" | grep -q '"errors": *true'; then
            error_count=$(echo "$bulk_response" | grep -o '"error":' | wc -l)
            echo "Bulk import completed with $error_count errors. Check Elasticsearch logs for details."
        else
            echo "Bulk import completed successfully."
        fi
    fi
    echo "Data import completed successfully."
}

main_menu
