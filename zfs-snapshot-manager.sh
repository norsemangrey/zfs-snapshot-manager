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
property_names=("Property")
property_counts=("Datasets")

while IFS= read -r property; do
  property_count=$(echo "$datasets_with_snapshot_config" | grep -c "$property")
  property_names+=("$property")
  property_counts+=("$property_count")
done <<< "$dataset_snapshot_property_names"

# Create a table with property names, counts, and index
datasets_snapshot_property_table=()
for ((i=0; i<${#property_names[@]}; i++)); do
  if [[ $i -eq 0 ]]; then
    index="#"
  else
    index=$((i))
  fi
  datasets_snapshot_property_table+=("$index ${property_names[i]} ${property_counts[i]}")
done

# Store unique snapshot names and their counts in arrays
snapshot_names=("Name")
snapshot_counts=("Snapshots")

while IFS= read -r snapshot; do
  snapshot_count=$(echo "$dataset_snapshots" | grep -c "$snapshot")
  snapshot_names+=("$snapshot")
  snapshot_counts+=("$snapshot_count")
done <<< "$dataset_snapshot_names"

# Create a table with snapshot names, counts, and index
dataset_snapshot_names_table=()
for ((i=0; i<${#snapshot_names[@]}; i++)); do
  if [[ $i -eq 0 ]]; then
    index="#"
  else
    index=$((i))
  fi
  dataset_snapshot_names_table+=("$index ${snapshot_names[i]} ${snapshot_counts[i]}")
done

# Store unique snapshot hold tags and their counts in arrays
hold_names=("Tag")
hold_counts=("Snapshots")

while IFS= read -r hold; do
  hold_count=$(echo "$dataset_snapshots_with_holds" | grep -c "$hold")
  hold_names+=("$hold")
  hold_counts+=("$hold_count")
done <<< "$dataset_snapshot_hold_tags"

# Create a table with snapshot names, counts, and index
dataset_snapshot_holds_table=()
for ((i=0; i<${#hold_names[@]}; i++)); do
  if [[ $i -eq 0 ]]; then
    index="#"
  else
    index=$((i))
  fi
  dataset_snapshot_holds_table+=("$index ${hold_names[i]} ${hold_counts[i]}")
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

function display_datasets() {

  # Print the table using the 'column' command
  echo "######  Properties  ######"
  echo ""
  printf '%s\n' "${datasets_snapshot_property_table[@]}" | column -t
  echo ""

  # Ask the user to select a property
  read -p "List datasets by entering property index ('m' for menu or 'q' to quit): " selected_index
  echo ""
  echo "---------------------------------------------------------------------------------------------"
  echo ""

  # Check if the user wants to quit
  if [[ "$selected_index" == "q" ]]; then
    exit 0
  fi

    # Check if the user wants to return to menu
  if [[ "$selected_index" == "m" ]]; then
    show_menu
    return
  fi  

  # Validate the user's input
  if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -lt 1 || "$selected_index" -ge ${#property_names[@]} ]]; then
    echo "Invalid selection. Please enter a valid index."
    echo ""
    display_datasets
    return
  fi

  # Get the selected property
  selected_property=${property_names[selected_index]}

  # Display datasets with the selected property
  #zfs get -H -o name,property,value $selected_property -s local -t filesystem } | column -t
  datasets_with_snapshot_properties_table_print=("${datasets_with_snapshot_properties_table_headers}" "${datasets_with_snapshot_properties_table[@]}")
  printf '%s\n' "${datasets_with_snapshot_properties_table_print[@]}" | grep "$selected_property\|$datasets_with_snapshot_properties_table_headers" | column -t
  echo ""
  echo "---------------------------------------------------------------------------------------------"
  echo ""

  display_datasets

}

function display_snapshots() {

  # Print the table using the 'column' command
  echo "######  Snapshots  ######"
  echo ""
  printf '%s\n' "${dataset_snapshot_names_table[@]}" | column -t
  echo ""

  # Ask the user to select a snapshot name
  read -p "List snapshots by entering snapshot name index ('m' for menu or 'q' to quit): " selected_index
  echo ""
  echo "---------------------------------------------------------------------------------------------"
  echo ""

  # Check if the user wants to quit
  if [[ "$selected_index" == "q" ]]; then
    exit 0
  fi

    # Check if the user wants to return to menu
  if [[ "$selected_index" == "m" ]]; then
    show_menu
    return
  fi  

  # Validate the user's input
  if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -lt 1 || "$selected_index" -ge ${#snapshot_names[@]} ]]; then
    echo "Invalid selection. Please enter a valid index."
    echo ""
    display_snapshots
    return
  fi

  # Get the selected property
  selected_snapshot=${snapshot_names[selected_index]}

  # Display snapshot with the selected name
  #zfs list -H -o name -t snapshot | grep $selected_snapshot  | column -t
  dataset_snapshots_table_print=("${dataset_snapshots_table_headers}" "${dataset_snapshots_table[@]}")
  printf '%s\n' "${dataset_snapshots_table_print[@]}" | grep "$selected_snapshot\|$dataset_snapshots_table_headers" | column -t
  echo ""
  echo "---------------------------------------------------------------------------------------------"
  echo ""

  display_snapshots

}

function display_holds() {

  # Print the table using the 'column' command
  echo "######  Holds  #######"
  echo ""
  printf '%s\n' "${dataset_snapshot_holds_table[@]}" | column -t
  echo ""

  # Ask the user to select a hold tag
  read -p "List snapshots by entering hold name index ('m' for menu or 'q' to quit): " selected_index
  echo ""
  echo "---------------------------------------------------------------------------------------------"
  echo ""

  # Check if the user wants to quit
  if [[ "$selected_index" == "q" ]]; then
    exit 0
  fi

    # Check if the user wants to return to menu
  if [[ "$selected_index" == "m" ]]; then
    show_menu
    return
  fi  

  # Validate the user's input
  if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -lt 1 || "$selected_index" -ge ${#hold_names[@]} ]]; then
    echo "Invalid selection. Please enter a valid index."
    echo ""
    display_holds
    return
  fi

  # Get the selected hold tag
  selected_holds=${hold_names[selected_index]}

  # Display snapshots with the selected hold tag
  #echo "$dataset_snapshots" | tr '\n' '\0' | xargs -0 zfs holds -H | grep $selected_holds  | column -t
  dataset_snapshots_table_print=("${dataset_snapshots_table_headers}" "${dataset_snapshots_table[@]}")
  printf '%s\n' "${dataset_snapshots_table_print[@]}" | grep "$selected_holds\|$dataset_snapshots_table_headers" | column -t
  echo ""q

  echo "---------------------------------------------------------------------------------------------"
  echo ""

  display_holds

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
    2) display_datasets ;;
    3) display_snapshots ;;
    4) display_holds ;;
    5) display_datasets_without_snapshots ;;
    6) display_snapshots_without_properties ;;
    q) exit 0 ;;
    *) echo "Invalid option. Please try again."
       echo ""
       show_menu ;;
  esac
}

show_menu