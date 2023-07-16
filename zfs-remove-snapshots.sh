#!/bin/bash

BOLD="\e[1m"
CLEAR="\e[0m"

if [ "$1" == "" ]; then
  echo "You need to specify a root dataset"
  exit 1
fi

dataset=$1
echo "Searching for snapshots under $dataset"
echo ""

# Get a list of snapshots for the given dataset
snapshots=($(zfs list -H -t snapshot -o name -r "$dataset"))

if [ ${#snapshots[@]} -eq 0 ]; then
  echo "No snapshots found"
else
  echo "Snapshots found:"
  echo ""
  snapshot_col=("Snapshot")
  holds_col=("Hold Tags")
  snapshot_dataset_col=("Dataset")
  snapshot_part_col=("Snapshot")
  for snapshot in "${snapshots[@]}"; do
    # Extract the second part of the snapshot name
    snapshot_dataset=$(echo "$snapshot" | awk -F@ '{print $1}')
    snapshot_part=$(echo "$snapshot" | awk -F@ '{print $2}')
    snapshot_col+=("$snapshot")
    snapshot_dataset_col+=("$snapshot_dataset")
    snapshot_part_col+=("$snapshot_part")

    # Check if the snapshot has any hold tags
    holds=($(zfs holds -H "$snapshot" | awk '{ print $2 }'))
    if [ ${#holds[@]} -eq 0 ]; then
      holds_col+=("None")
    else
      holds_str=$(IFS=$'\n'; echo "${holds[*]}")
      holds_col+=("$holds_str")
    fi
  done

  # Output the table with snapshots, holds, and snapshot parts
  paste <(printf "%s\n" "${snapshot_dataset_col[@]}") <(printf "%s\n" "${snapshot_part_col[@]}") <(printf "%s\n" "${holds_col[@]}") | column -t -s $'\t' | {
    IFS= read -r header
    printf '%s\n' "$(tput bold)$header$(tput sgr0)"
    cat
  }

  echo ""

  unique_parts=()
  for snapshot in "${snapshots[@]}"; do
    snapshot_part=$(echo "$snapshot" | awk -F@ '{print $2}')
    if [[ ! " ${unique_parts[@]} " =~ " ${snapshot_part} " ]]; then
      unique_parts+=("$snapshot_part")
    fi
  done

  # Output the list of unique snapshot parts
  echo -e  "${BOLD}Unique Snapshot Names:${CLEAR}"
  for index in "${!unique_parts[@]}"; do
    echo "$((index+1)). ${unique_parts[index]}"
  done

  # Prompt user for options
  read -r -p "Do you want to apply actions to (A)ll snapshots or (S)elected snapshots? (A/S): " choice

  if [[ "$choice" =~ ^[Aa]$ ]]; then
    # Apply actions to all snapshots
    selected_snapshots=("${snapshots[@]}")
  elif [[ "$choice" =~ ^[Ss]$ ]]; then
    # Apply actions to selected snapshots
    read -r -p "Enter the numbers of the snapshot parts to select (comma-separated): " selected_indices
    IFS=',' read -r -a indices_array <<< "$selected_indices"
    selected_snapshots=()
    for index in "${indices_array[@]}"; do
      if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 )) && (( index <= ${#unique_parts[@]} )); then
        selected_snapshots+=($(printf "%s\n" "${snapshots[@]}" | grep "${unique_parts[index-1]}"))
      else
        echo "Invalid selection: $index"
      fi
    done
  else
    echo "Invalid choice. Exiting."
    exit 1
  fi

  if [ ${#selected_snapshots[@]} -eq 0 ]; then
    echo "No selected snapshots found. Exiting."
    exit 0
  fi

  # Prompt user for action
  read -r -p "Do you want to (D)elete snapshots and release holds, (R)elease holds only, or (C)ancel? (D/R/C): " response

  if [[ "$response" =~ ^[Dd]$ ]]; then
    # User chose to delete snapshots and release holds
    for snapshot in "${selected_snapshots[@]}"; do
      echo "Destroying snapshot: $snapshot"
      # Check if the snapshot has any hold tags
      holds=($(zfs holds -H "$snapshot" | awk '{ print $2 }'))
      if [ ${#holds[@]} -ne 0 ]; then
        for hold in "${holds[@]}"; do
          echo "Releasing hold tag: $hold"
          # Remove hold tags on the snapshot
          zfs release -r "$hold" "$snapshot"
        done
      fi
      echo "Removing snapshot: $snapshot"
      zfs destroy "$snapshot"
    done
  elif [[ "$response" =~ ^[Rr]$ ]]; then
    # User chose to release holds only
    for snapshot in "${selected_snapshots[@]}"; do
      holds=($(zfs holds -H "$snapshot" | awk '{ print $2 }'))
      if [ ${#holds[@]} -ne 0 ]; then
        for hold in "${holds[@]}"; do
          echo "Releasing hold tag: $hold"
          # Remove hold tags on the snapshot
          zfs release -r "$hold" "$snapshot"
        done
      fi
    done
    echo "Hold tags released. Snapshots were not deleted."
  else
    echo "Action canceled. No snapshots or hold tags were modified."
  fi
fi

exit 0
