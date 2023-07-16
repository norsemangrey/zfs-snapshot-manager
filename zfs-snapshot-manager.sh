#!/bin/bash

# Formatting constants.
BOLD="\e[1m"
CLEAR="\e[0m"

# Create snapshots table with tab-separated values
dataset_snapshots_table=()
index=1
while IFS=$'\t' read -r snapshot creation_date; do

  dataset_name=$(echo "$snapshot" | cut -d '@' -f 1)
  snapshot_name=$(echo "$snapshot" | cut -d '@' -f 2)
  dataset_properties=$(zfs get all "$snapshot" | awk '{print $2}' | grep ':' | sort | paste -s -d, -)
  if [[ -z "$dataset_properties" ]]; then
    dataset_properties="-"
  fi
  hold_tags=$(zfs holds -H "$snapshot" | awk '{print $2}' | sort | paste -s -d, -)
  if [[ -z "$hold_tags" ]]; then
    hold_tags="-"
  fi

  dataset_snapshots_table+=("$index $dataset_name $snapshot_name $dataset_properties $hold_tags $creation_date")
  ((index++))

done < <(zfs list -H -o name,creation -t snapshot | grep -v dataset)

dataset_snapshots_table_headers=("ID Dataset Snapshot Properties Holds Created")

# Get a list of all snapshot names (exclude selected)
dataset_snapshots=$(zfs list -H -o name -t snapshot | grep -v datasets)

# Get a snapshot count
dataset_snapshot_count=$(echo "$dataset_snapshots" | wc -l)

# Get unique snapshot names
dataset_snapshot_names=$(echo "$dataset_snapshots" | awk -F'@' '{print $2}' | sort | uniq)

# Extract snaspshot dataset names
dataset_snapshot_dataset_names=$(echo "$dataset_snapshots" | awk -F'@' '{print $1}')

# Get all snapshots with hold tags.
dataset_snapshots_with_holds=$(echo "$dataset_snapshots" | tr '\n' '\0' | xargs -0 zfs holds -H | sort)

# Get a count of snapshots with hold tags.
dataset_snapshots_with_holds_count=$(echo "$dataset_snapshots_with_holds" | wc -l)

# Get unique hold tag names.
dataset_snapshot_hold_tags=$(echo "$dataset_snapshots_with_holds" | awk '{print $2}' | uniq)

# Get unique datasets that has snapshots
datasets_with_snapshots=$(echo "$dataset_snapshot_dataset_names" | sort | uniq)

# Get a count of the number of datasets with snapshots
datasets_with_snapshots_count=$(echo "$datasets_with_snapshots" | wc -l)

# Get snapshots that has a property set for automatic snapshot (TODO: Revice grep argument)
datasets_with_snapshot_config=$(zfs get -o name,property,value -s local all | grep ":")

# Extract the dataset names from the datasets
datasets_with_snapshot_properties=$(echo "$datasets_with_snapshot_config" | awk '{print $1}' | sort | uniq)
datasets_with_snapshot_properties_count=$(echo "$datasets_with_snapshot_properties" | wc -l)

datasets_with_snapshot_properties_table=()
index=1
while IFS=$'\t' read -r dataset property value; do 
  datasets_with_snapshot_properties_table+=("$index $dataset $property $value")
  ((index++))
done <<< "$datasets_with_snapshot_config"

datasets_with_snapshot_properties_table_headers=("ID Dataset Property Value")

# Extract the snapshot property names from the datasets
dataset_snapshot_property_names=$(echo "$datasets_with_snapshot_config" | awk '{print $2}' | sort | uniq)

# Compare dataset lists to find the differences
datasets_with_properties_without_snapshots=$(comm -23 <(echo "$datasets_with_snapshot_properties") <(echo "$datasets_with_snapshots"))
datasets_with_snapshots_without_properties=$(comm -13 <(echo "$datasets_with_snapshot_properties") <(echo "$datasets_with_snapshots"))
datasets_with_properties_without_snapshots_count=$(echo "$datasets_with_properties_without_snapshots" | sed '/^\s*$/d' | wc -l)
datasets_with_snapshots_without_properties_count=$(echo "$datasets_with_snapshots_without_properties" | sed '/^\s*$/d' | wc -l)

# Store unique properties and their counts in arrays
property_names=("")
property_counts=("")

while IFS= read -r property; do
  property_count=$(echo "$datasets_with_snapshot_config" | grep -c "$property")
  property_names+=("$property")
  property_counts+=("$property_count")
done <<< "$dataset_snapshot_property_names"

datasets_snapshot_property_table=("ID Property Datasets")
for ((i=1; i<${#property_names[@]}; i++)); do
  datasets_snapshot_property_table+=("$i ${property_names[i]} ${property_counts[i]}")
done

# Store unique snapshot names and their counts in arrays
snapshot_names=("")
snapshot_counts=("")

while IFS= read -r snapshot; do
  snapshot_count=$(echo "$dataset_snapshots" | grep -c "$snapshot")
  snapshot_names+=("$snapshot")
  snapshot_counts+=("$snapshot_count")
done <<< "$dataset_snapshot_names"

dataset_snapshot_names_table=("ID Name Snapshots")
for ((i=1; i<${#snapshot_names[@]}; i++)); do
  dataset_snapshot_names_table+=("$i ${snapshot_names[i]} ${snapshot_counts[i]}")
done

# Store unique snapshot hold tags and their counts in arrays
hold_names=("")
hold_counts=("")

while IFS= read -r hold; do
  hold_count=$(echo "$dataset_snapshots_with_holds" | grep -c "$hold")
  hold_names+=("$hold")
  hold_counts+=("$hold_count")
done <<< "$dataset_snapshot_hold_tags"


dataset_snapshot_holds_table=("ID Tag Snapshots")
for ((i=1; i<${#hold_names[@]}; i++)); do
  dataset_snapshot_holds_table+=("$i ${hold_names[i]} ${hold_counts[i]}")
done


function display_summary() {

  echo "Total snapshots: ${dataset_snapshot_count}"
  echo "Datasets with snapshots: ${datasets_with_snapshots_count}"
  echo "Datasets with snapshot properties: ${datasets_with_snapshot_properties_count}"
  echo "Datasets with snapshot properties, but no snapshots: ${datasets_with_properties_without_snapshots_count}"
  echo "Datasets with snapshots, but no snapshot properties: ${datasets_with_snapshots_without_properties_count}"
  echo "Snapshots with holds: ${dataset_snapshots_with_holds_count}"
  echo ""

  show_menu

} 

function display_datasets_without_snapshots() {
  # Check if there are datasets without snapshots
  if [[ "$datasets_with_properties_without_snapshots_count" -eq 0 ]]; then
    echo "No datasets without snapshots."
    echo ""
  else
    # Print the list of datasets without snapshots
    echo "Datasets without snapshots:"
    echo ""
    printf '%s\n' "${datasets_with_properties_without_snapshots[@]}"
    echo ""
  fi

  show_menu
}

function display_snapshots_without_properties() {
  # Check if there are snapshots without properties
  if [[ "$datasets_with_snapshots_without_properties_count" -eq 0 ]]; then
    echo "No snapshots without properties."
    echo ""
  else
    # Print the list of snapshots without properties
    echo "Snapshots without properties:"
    echo ""
    printf '%s\n' "${datasets_with_snapshots_without_properties[@]}"
    echo ""
  fi

  show_menu
}

function display_table() {

  local table_name="$1"
  local -n table_content=$2

  echo "######  $table_name  ######"
  echo ""
  printf '%s\n' "${table_content[@]}" | column -t
  echo ""
}

function display_items() {

  local item_type="$1"
  local item_name="$2"
  local item_index="$3"
  local -n table_overview=$4
  local -n table_main=$5
  local -n table_headers=$6

  local table_overview_local=("${table_overview[@]}")
  local table_main_local=("${table_main[@]}")
  local table_headers_local=("${table_headers[@]}")

  display_table "$item_type" table_overview

  read -p "List $item_name by entering $item_type index ('m' for menu or 'q' to quit): " selected_index
  echo ""

  # Check if the user wants to quit
  if [[ "$selected_index" == "q" ]]; then
    exit 0
  fi

  # Check if the user wants to return to the menu
  if [[ "$selected_index" == "m" ]]; then
    show_menu
    return
  fi

  # Validate the user's input
  if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -lt 1 || "$selected_index" -ge ${#table_overview[@]} ]]; then
    echo "Invalid selection. Please enter a valid index."
    echo ""
    display_items "$item_type" "$item_name" "$item_index" table_overview_local table_main_local table_headers_local
    return
  fi

  # Get the selected item
  local selected_item=$(echo "${table_overview[selected_index]}" | awk '{print $2}')

  local table_print=("${table_headers}" "${table_main[@]}")

  printf '%s\n' "${table_print[@]}" | grep "$selected_item\|$table_headers" | column -t
  echo ""

  display_items "$item_type" "$item_name" "$item_index" table_overview_local table_main_local table_headers_local

}

function show_menu() {

  echo ""
  echo "#######  ZFS MANAGER - MAIN MENU  ########"
  echo "#                                        #"
  echo "#  Select an option:                     #"
  echo "#                                        #"
  echo "#  1. Show summary                       #"
  echo "#  2. List datasets by properties        #"
  echo "#  3. List snapshots by name             #"
  echo "#  4. List snapshots by hold             #"
  echo "#  5. List datasets without snapshots    #"
  echo "#  6. List snapshots without properties  #"
  echo "#                                        #" 
  echo "#  q. Quit                               #"
  echo "#                                        #"
  echo "##########################################"
  echo ""

  read -p "Enter your choice: " choice
  echo ""

  case "$choice" in
    1) display_summary ;;
    2) display_items "Properties" "datasets" 1 datasets_snapshot_property_table datasets_with_snapshot_properties_table datasets_with_snapshot_properties_table_headers;;
    3) display_items "Snapshots" "snapshots" 1 dataset_snapshot_names_table dataset_snapshots_table dataset_snapshots_table_headers;;
    4) display_items "Holds" "snapshots" 1 dataset_snapshot_holds_table dataset_snapshots_table dataset_snapshots_table_headers;;
    5) display_datasets_without_snapshots ;;
    6) display_snapshots_without_properties ;;
    q) exit 0 ;;
    *) echo "Invalid option. Please try again."
       echo ""
       show_menu ;;
  esac
}

show_menu