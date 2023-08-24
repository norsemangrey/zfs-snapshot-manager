#!/bin/bash

# Formatting constants.
BOLD="\e[1m"
RED="\e[91m"
GREEN="\e[92m"
CLEAR="\e[0m"

dry_run=false
include_parents=false
top_dataset=""
user=$(whoami)

# Exludes Docker generated datasets and USB connected drives.
exclude_datasets="datasets/|external"

function usage() {
  echo "Usage: $0 [-d] [-p] --top <top_dataset>"
  echo "Options:"
  echo "  -d, --dry-run   Perform a dry run (no zfs commands will be executed)"
  echo "  -t, --top       Set the top dataset for ZFS snapshots data collection"
  echo "  -p, --parents   Include parents of selected top dataset"
  exit 1
}

options=$(getopt -o dpr: --long dry-run,top,parents: -n 'zfs_snapshot_manager.sh' -- "$@")
if [ $? -ne 0 ]; then
  echo "Error: Invalid option"
  usage
fi

eval set -- "$options"
while true; do
  case "$1" in
    -d | --dry-run)
      dry_run=true
      shift ;;
    -p | --parents)
      include_parents=true
      shift ;;
    -r | --top)
      top_dataset="$2"
      shift 2 ;;
    --)
      shift; break ;;
    *)
      echo "Internal error!"
      exit 1 ;;
  esac
done

# Validate the top dataset if provided
if [ -n "$top_dataset" ]; then

  if ! zfs list -H "$top_dataset" &>/dev/null; then
    echo "Error: Top dataset '$top_dataset' does not exist."
    exit 1
  fi

  IFS="/" read -ra dataset_parts <<< "$top_dataset"
  root_dataset=${dataset_parts[0]}

fi

function gather_snapshot_data() {

  echo "Collecting data, please wait ..."
  echo ""

  dataset_list=""
  snapshot_list=""

  # Get parents dataset names and snapshots.
  if [[ "$include_parents" == true && -n "$top_dataset" ]]; then

    parent=""
    for ((i=0; i<${#dataset_parts[@]}-1; i++)); do
        parent="$parent${dataset_parts[i]}"
        dataset_list="$dataset_list$parent"$'\n'
        snapshot_list="$snapshot_list$(zfs list -H -o name,creation -t snapshot $parent)"$'\n'
        parent="$parent/"
    done

  fi

  snapshot_list="$snapshot_list$(zfs list -H -o name,creation -t snapshot -r $top_dataset | grep -vE $exclude_datasets)"

  # Create snapshot tables with tab-separated values
  dataset_snapshots_table=()
  dataset_snapshots_with_hold_table=()
  index=1
  while IFS=$'\t' read -r snapshot creation_date; do

    dataset_name=$(echo "$snapshot" | cut -d '@' -f 1)
    snapshot_name=$(echo "$snapshot" | cut -d '@' -f 2)

    # Find datasets that has a custom property (:) set to 'true'.
    dataset_properties=$(zfs get all -H -o property,value "$snapshot" | grep -E ':.*true' | awk '{print $1}' | sort | paste -s -d, -)
    
    if [[ -z "$dataset_properties" ]]; then

      dataset_properties="-"

    fi

    hold_tags=$(zfs holds -H "$snapshot" | awk '{print $2}' | sort | paste -s -d, -)

    if [[ -z "$hold_tags" ]]; then

      hold_tags="-"

    else

      dataset_snapshots_with_hold_table+=("$index $dataset_name $snapshot_name $dataset_properties $hold_tags $creation_date")

    fi

    dataset_snapshots_table+=("$index $dataset_name $snapshot_name $dataset_properties $hold_tags $creation_date")
    ((index++))

  done <<< "$snapshot_list"
  dataset_snapshots_count=${#dataset_snapshots_table[@]}
  dataset_snapshots_with_hold_count=${#dataset_snapshots_with_hold_table[@]}
  dataset_snapshots_table_headers=("ID Dataset Snapshot Properties Holds Created")

  dataset_list="$dataset_list$(zfs list -H -o name -t filesystem -r $top_dataset | grep -vE $exclude_datasets)"

  # Create dataset tables with tab-separated values
  datasets_table=()
  datasets_with_property_table=()
  datasets_with_snapshot_table=()
  datasets_without_snapshot_table=()
  datasets_without_property_table=()
  datasets_with_property_no_snapshot_table=()
  datasets_with_snapshot_no_property_table=()
  index=1
  while IFS=$'\t' read -r dataset; do

    get_permissions "$dataset"

    if [[ -z "$permissions" ]]; then

      permissions="-"

    fi

    # Find datasets that has a custom property (:) set to 'true'.
    properties=$(zfs get all -H -o property,value "$dataset" | grep -E ':.*true' | awk '{print $1}' | sort | paste -s -d, -)

    snapshots=$(zfs list -t snapshot -H -o name "$dataset" | grep -c '@')

    if [[ -z "$properties" ]]; then

      properties="-"

      datasets_without_property_table+=("$index $dataset $properties $snapshots $permissions")

      if [[ $snapshots -lt 1 ]]; then

        datasets_without_snapshot_table+=("$index $dataset $properties $snapshots $permissions")

      else

        datasets_with_snapshot_no_property_table+=("$index $dataset $properties $snapshots $permissions")

        datasets_with_snapshot_table+=("$index $dataset $properties $snapshots $permissions")

      fi

    else

      datasets_with_property_table+=("$index $dataset $properties $snapshots $permissions")

      if [[ $snapshots -lt 1 ]]; then

        datasets_without_snapshot_table+=("$index $dataset $properties $snapshots $permissions")

        datasets_with_property_no_snapshot_table+=("$index $dataset $properties $snapshots $permissions")

      else

        datasets_with_snapshot_table+=("$index $dataset $properties $snapshots $permissions")

      fi

    fi

    datasets_table+=("$index $dataset $properties $snapshots $permissions")

    ((index++))

  done <<< "$dataset_list"
  datasets_count=${#datasets_table[@]}
  datasets_with_property_count=${#datasets_with_property_table[@]}
  datasets_with_snapshots_count=${#datasets_with_snapshot_table[@]}
  datasets_without_snapshots_count=${#datasets_without_snapshot_table[@]}
  datasets_without_property_count=${#datasets_without_property_table[@]}
  datasets_with_property_no_snapshot_count=${#datasets_with_property_no_snapshot_table[@]}
  datasets_with_snapshot_no_property_count=${#datasets_with_snapshot_no_property_table[@]}
  datasets_table_headers=("ID Dataset Properties Snapshots Permissions(L|D)")

  # Store unique properties and their counts in tables
  if [[ "$datasets_with_property_count" -gt 0 ]]; then

    # Get all datasets with snapshot properties and a list of unique property names
    datasets_with_snapshot_properties=$(echo "$dataset_list" | tr '\n' '\0' | xargs -0 zfs get -o name,property,value -s local all | grep ':')
    dataset_snapshot_property_names=$(echo "$datasets_with_snapshot_properties" | awk '{print $2}' | sort | uniq)

    property_names=("")
    property_counts=("")


    while IFS= read -r property; do
      property_count=$(echo "$datasets_with_snapshot_properties" | grep 'true' | grep -c "$property" )
      property_names+=("$property")
      property_counts+=("$property_count")
    done <<< "$dataset_snapshot_property_names"

    datasets_snapshot_property_table=("ID Property Datasets")
    for ((i=1; i<${#property_names[@]}; i++)); do
      datasets_snapshot_property_table+=("$i ${property_names[i]} ${property_counts[i]}")
    done

  fi

  # Store unique snapshot names and their counts in table
  if [[ "$dataset_snapshots_count" -gt 0 ]]; then

    # Get all snapshots (exclude selected) and  a list of unique snapshot names
    dataset_snapshots=$(echo "$dataset_list" | tr '\n' '\0' | xargs -0 zfs list -H -o name -t snapshot)
    dataset_snapshot_names=$(echo "$dataset_snapshots" | awk -F'@' '{print $2}' | sort | uniq)

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

  fi

  # Store unique snapshot hold tags and their counts in table
  if [[ "$dataset_snapshots_with_hold_count" -gt 0 ]]; then 

    # Get all snapshots with hold tags and a list of unique tag names
    dataset_snapshots_with_holds=$(echo "$dataset_snapshots" | tr '\n' '\0' | xargs -0 zfs holds -H | sort | sed '/^\s*$/d')
    dataset_snapshot_hold_tags=$(echo "$dataset_snapshots_with_holds" | awk '{print $2}' | uniq)

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

  fi

} 

function get_permissions() {

  local dataset="$1"

  # Run the zfs command and filter the output using awk
  zfs_output=$(zfs allow "$dataset")
  permissions=$(echo "$zfs_output" | awk -v path="$dataset" '
      BEGIN { in_local_section = 0; in_descendent_section = 0 }
      /^---- Permissions on / {
          if (in_local_section) {
              in_local_section = 0
          }
          if (in_descendent_section) {
              in_descendent_section = 0
          }
          section_path = $4
      }
      $0 ~ "Local\\+Descendent permissions:" && section_path == path {
          in_local_section = 1
          next
      }
      $0 ~ "Descendent permissions:" && section_path == path {
          in_descendent_section = 1
          next
      }
      (in_local_section || in_descendent_section) && $0 ~ /^[[:space:]]+/ {
          # Split the line using spaces and print from the third field onwards
          for (i = 3; i <= NF; i++) {
              permission = $i
              if (i < NF) {
                  permission = permission ","
              }
              if (in_local_section) {
                  local_permissions = local_permissions permission
              } else if (in_descendent_section) {
                  descendent_permissions = descendent_permissions permission
              }
          }
      }
      (in_local_section || in_descendent_section) && NF == 0 {
          in_local_section = 0
          in_descendent_section = 0
      }
      END {
          if (descendent_permissions) {
              local_permissions = local_permissions "|"
          }
          printf local_permissions descendent_permissions
      }
  ')

}

function display_summary() {

  local summary_table=()
  summary_table+=("ID | Description | Count")
  summary_table+=("1 | Snapshots Total | $dataset_snapshots_count")
  summary_table+=("2 | Snapshots w/Holds | $dataset_snapshots_with_hold_count")
  summary_table+=("3 | Datasets Total | $datasets_count")
  summary_table+=("4 | Datasets w/Snapshots | $datasets_with_snapshots_count")
  summary_table+=("5 | Datasets w/Snapshots, wo/Snapshot Properties | $datasets_with_snapshot_no_property_count")
  summary_table+=("6 | Datasets wo/Snapshots | $datasets_without_snapshots_count")
  summary_table+=("7 | Datasets w/Snapshot Properties | $datasets_with_property_count")
  summary_table+=("8 | Datasets w/Snapshot Properties, wo/Snapshots | $datasets_with_property_no_snapshot_count")
  summary_table+=("9 | Datasets wo/Snapshot Properties | $datasets_without_property_count")


  echo "###############  SUMMARY  #################"
  echo ""
  printf '%s\n' "${summary_table[@]}" | column -t -s "|"
  echo ""
  
  read -p "Enter the ID to list items, go back to (M)enu or (Q)uit: " selected_index
  echo ""

  # Check if the user wants to quit
  if [[ "$selected_index"  =~ ^[Qq]$ ]]; then
    exit 0
  fi

  # Check if the user wants to return to the menu
  if [[ "$selected_index"  =~ ^[Mm]$ ]]; then
    show_menu
    return
  fi

  # Validate the user's input
  if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -lt 1 || "$selected_index" -gt 9 ]]; then
    echo "Invalid selection. Please enter a valid index."
    echo ""
    display_summary
    return
  fi

  case "$selected_index" in
    1) display_list_table "" "snapshots" ${dataset_snapshots_count} dataset_snapshots_table_headers dataset_snapshots_table ;;
    2) display_list_table "" "snapshots" ${dataset_snapshots_with_hold_count} dataset_snapshots_table_headers dataset_snapshots_with_hold_table ;;
    3) display_list_table "" "datasets" ${datasets_count} datasets_table_headers datasets_table ;;
    4) display_list_table "" "datasets" ${datasets_with_snapshots_count} datasets_table_headers datasets_with_snapshot_table ;;
    5) display_list_table "" "datasets" ${datasets_with_snapshot_no_property_count} datasets_table_headers datasets_with_snapshot_no_property_table ;;    
    6) display_list_table "" "datasets" ${datasets_without_snapshots_count} datasets_table_headers datasets_without_snapshot_table ;;    
    7) display_list_table "" "datasets" ${datasets_with_property_count} datasets_table_headers datasets_with_property_table ;;
    8) display_list_table "" "datasets" ${datasets_with_property_no_snapshot_count} datasets_table_headers datasets_with_property_no_snapshot_table ;;
    9) display_list_table "" "datasets" ${datasets_without_property_count} datasets_table_headers datasets_without_property_table ;;
    m) show_menu 
       return ;;
    q) exit 0 ;;
    *) echo "Invalid selection. Please enter a valid index."
       echo ""
       display_summary ;;
  esac

  display_summary

} 

function display_unique_table() {

  local table_name="$1"
  local -n table_content=$2

  echo "############  $table_name  ###########"
  echo ""
  printf '%s\n' "${table_content[@]}" | column -t
  echo ""

}

function display_list_table() {

  local filter="$1"
  local type="$2"
  local count="$3"
  local -n headers=$4
  local -n table=$5

  if [[ "$count" -eq 0 ]]; then

    echo "No items to display."
    echo ""

  else

    local filtered_table=()
    for item in "${table[@]}"; do
      if echo "$item" | grep -q "$filter"; then
        filtered_table+=("$item")
      fi
    done

    local print=("${headers}" "${filtered_table[@]}")

    echo "Items: $count"

    echo "---------------------------------------------------------------------------------------------------------------------------"
    echo ""
    printf '%s\n' "${print[@]}" | column -t
    echo ""
    echo "---------------------------------------------------------------------------------------------------------------------------"
    echo ""

    # Prompt user for options
    read -r -p "Do you want to apply actions to (A)ll items, (S)elected items or go (B)ack?: " choice
    echo ""

    if [[ "$choice" =~ ^[Aa]$ ]]; then

      # Apply actions to all items
      selected=("${filtered_table[@]}")

    elif [[ "$choice" =~ ^[Ss]$ ]]; then

      # Apply actions to selected items
      while true; do

        read -r -p "Enter the ID of the items to select (comma-separated): " selected_ids
        echo ""

        if [[ ! "$selected_ids" =~ ^[0-9]+(,[0-9]+)*$ ]]; then

          echo "Invalid input. Please enter a list of comma-separated numbers."
          echo ""

        else

          IFS="," read -r -a selected_ids_arr <<< "$selected_ids"

          local valid_input=true

          selected=()
          for id in "${selected_ids_arr[@]}"; do

            local found=false

            for item in "${filtered_table[@]}"; do

              if [[ "$item" == "$id "* ]]; then
                selected+=("$item")
                found=true
                break
              fi

            done

            if [[ "$found" == false ]]; then
              valid_input=false
              break
            fi

          done

          if [[ "$valid_input" == true ]]; then
            break
          else
            echo "Invalid ID(s) provided. Please enter valid ID(s) from the list."
            echo ""
          fi

        fi

      done

    elif [[ "$choice" =~ ^[Bb]$ ]]; then

      return

    else

      echo "Invalid selection."
      echo ""
      return

    fi

    # Display the selected items
    if [[ ${#selected[@]} -eq 0 ]]; then
      echo "No items selected."
      echo ""
    else
      echo "Selected Items:"
      echo "---------------------------------------------------------------------------------------------------------------------------"
      echo ""
      printf '%s\n' "${headers}" "${selected[@]}" | column -t
      echo ""
      echo "---------------------------------------------------------------------------------------------------------------------------"
      echo ""
    fi

    if [[ "$type" == "snapshots" ]]; then

      echo " Select Action:"
      echo ""
      echo " 1. Release Holds"
      echo " 2. Destroy Snapshots"
      echo ""
      echo " b. Back"
      echo " q. Quit"
      echo ""
      echo "---------------------------------------------------------------------------------------------------------------------------"
      echo ""

      # Prompt user for action
      read -p "Enter your choice: " choice
      echo ""

      case "$choice" in
        1) remove_holds_delete_snapshots selected "$type" false ;;
        2) remove_holds_delete_snapshots selected "$type" true ;;
        b) return ;;
        q) exit 0 ;;
        *) echo "Invalid option. Please try again."
          echo ""
      esac

    fi

    if [[ "$type" == "datasets" ]]; then 

      echo " Select Action:"
      echo ""
      echo " 1. Set Property"
      echo " 2. Clear Property"
      echo " 3. Create Snapshot"
      echo " 4. Set Permissions"    
      echo " 5. Release Holds"
      echo " 6. Destroy Snapshots"
      echo ""
      echo " b. Back"
      echo " q. Quit"
      echo ""
      echo "---------------------------------------------------------------------------------------------------------------------------"
      echo ""

      # Prompt user for action
      read -p "Enter your choice: " choice
      echo ""

      case "$choice" in
        1) set_properties selected ;;
        2) clear_properties selected ;;
        3) create_snapshots selected ;;
        4) set_snapshot_permissions selected ;;
        5) remove_holds_delete_snapshots selected "$type" false ;;
        6) remove_holds_delete_snapshots selected "$type" true ;;
        b) return ;;
        q) exit 0 ;;
        *) echo "Invalid option. Please try again."
          echo ""
      esac

    fi

  fi

} 

function create_snapshots() {

  local -n items=$1

  local timestamp=$(date +%Y-%m-%dT%H:%M:%S)

  echo "Creating Snapshots"
  echo "---------------------------------------------------------------------"

  for item in "${items[@]}"; do

    dataset=$(echo "$item" | awk '{print $2}')
    echo ""
    echo "$dataset"

    snapshot=$(echo "$dataset@manual-$timestamp")  

    echo "   |"
    echo "   '--> [$snapshot]"
    echo "         Creating ..."

    if [[ "$dry_run" == false ]]; then
      sudo zfs snapshot $snapshot
    fi

  done

  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  if [[ "$dry_run" == false ]]; then
    
    main

  fi

}

function add_property() {

  local from_set_property="$1"
  local -n temp_items=$2
 
  local -r valid_input_pattern="^[0-9a-z_-]+$"

  echo "New Property Name / Value"
  echo ""

  while true; do

    read -r -p "Provide first part ('c' to cancel): " first
    echo ""

    # Check if the user wants to cancel
    if [[ "$first" == "c" ]]; then
      echo "Operation canceled. No properties were added."
      echo ""
      return
    fi

    if [[ ! "$first" =~ $valid_input_pattern ]]; then
      echo "Invalid input. Please only use numbers, lowercase characters, '-' and '_' in the first part."
      echo ""
    else
      break
    fi

  done

  while true; do

    read -r -p "Provide second part ('c' to cancel): " second
    echo ""

    # Check if the user wants to cancel
    if [[ "$second" == "c" ]]; then
      echo "Operation canceled. No properties were added."
      echo ""
      return
    fi

    if [[ ! "$second" =~ $valid_input_pattern ]]; then
      echo "Invalid input. Please only use numbers, lowercase characters, '-' and '_' in the second part."
      echo ""
    else
      break
    fi

  done

  local property=$(echo "$first:$second") 

  while true; do

    read -r -p "Provide property value ('c' to cancel, default=false): " value
    echo ""

    # Check if the user wants to cancel
    if [[ "$value" == "c" ]]; then
      echo "Operation canceled. No properties were added."
      echo ""
      return
    fi

    if [[ -z "$value" ]]; then
      value="false"
      break
    fi

    if [[ ! "$value" =~ ^[a-z]+$ ]]; then
      echo "Invalid input. Please only use lowercase characters for the value."
      echo ""
    else
      break
    fi

  done

  echo "Adding Propery"
  echo "---------------------------------------------------------------------"

  add_items=($(zfs list -H -o name -t filesystem -r $root_dataset | grep -vE $exclude_datasets))
  for item in "${add_items[@]}"; do

    dataset=$(echo "$item")

    echo ""
    echo "$dataset" 
    echo "   |"
    echo "   '--> [$property=$value]"
    echo "         Adding ..."

    if [[ "$dry_run" == false && "$property" == *":"* ]]; then
      sudo zfs set $property=$value $dataset 
    fi

  done

  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  if [[ "$from_set_property" == true ]]; then
  
    set_properties temp_items

  else

    main

  fi

}

function set_properties() {

  local -n set_items=$1

  local properties=()

  local properties=$(zfs get -o name,property,value -s local all -r | grep ':' | awk '{print $2}' | sort | uniq)

  if [[ -z $properties ]]; then

    local prompt="No custom properties found. Create a (N)ew property or (C)ancel: "
    echo ""
  
  else

    local index=1
    local properties_array=()
    while IFS= read -r property; do
        properties_array+=("$index $property")
        ((index++))
    done <<< "$properties"

    for prop in "${properties_array[@]}"; do
      echo "$prop"
    done
    echo ""
    
    local prompt="Enter the ID of the property to set for the selected datasets, create a (N)ew property or (C)ancel: "

  fi

  local selected_id=""
  while [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; do

    read -p "$prompt" selected_id
    echo ""

    if [[ "$selected_id" =~ ^[Cc]$  ]]; then
      echo "Operation canceled."
      echo ""
      return
    fi

    if [[ "$selected_id" =~ ^[Nn]$ ]]; then
      add_property true set_items
      return
    fi

    if [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; then
      echo "Invalid input. Please enter a valid ID or 'c' to cancel."
      echo ""
    fi

  done

  local property=""
  for prop in "${properties_array[@]}"; do
    if [[ "$prop" == "$selected_id "* ]]; then
      property=$(echo "$prop" | awk '{print $2}')
      break
    fi
  done

  echo "Setting Property"
  echo "---------------------------------------------------------------------"

  for item in "${set_items[@]}"; do

    dataset=$(echo "$item" | awk '{print $2}')

    echo ""
    echo "$dataset" 
    echo "   |"
    echo "   '--> [$property=true]"
    echo "         Setting ..."

    if [[ "$dry_run" == false && "$property" == *":"* ]]; then
      sudo zfs set $property=true $dataset 
    fi

  done

  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  if [[ "$dry_run" == false ]]; then
    
    main

  fi

}

function clear_properties() {

  local -n remove_items=$1

  local properties=()
  local index=1

  # Get unique properties for selected datasets
  for item in "${remove_items[@]}"; do

    properties_string=$(echo "$item" | awk '{print $3}')
    IFS=',' read -ra dataset_properties <<< "$properties_string"

    for property in "${dataset_properties[@]}"; do

      # Check if the property is not already in the properties array
      if [[ "$property" != "-" && ! " ${properties[*]} " =~ " $property " ]]; then
        properties+=("$index $property")
        ((index++))
      fi
      
    done

  done

  if [ "${#properties[@]}" -lt 1 ]; then
    echo "No properties found. Operation canceled."
    echo ""
    return
  fi

  for prop in "${properties[@]}"; do
    echo "$prop"
  done
  echo ""

  local selected_id=""
  while [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; do

    read -p "Enter the ID of the property to remove (or 'c' to cancel): " selected_id
    echo ""

    if [[ "$selected_id" == "c" ]]; then
      echo "Operation canceled."
      echo ""
      return
    fi

    if [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; then
      echo "Invalid input. Please enter a valid ID or 'c' to cancel."
      echo ""
    fi

  done

  local property=""
  for prop in "${properties[@]}"; do
    if [[ "$prop" == "$selected_id "* ]]; then
      property=$(echo "$prop" | awk '{print $2}')
      break
    fi
  done

  echo "Clear Propery"
  echo "---------------------------------------------------------------------"

  for item in "${remove_items[@]}"; do

    dataset=$(echo "$item" | awk '{print $2}')
    echo ""
    echo "$dataset" 
    echo "  |"
    echo "  '--> [$property=false]"
    echo "        Clearing ..."

    if [[ "$dry_run" == false && "$property" == *":"* ]]; then
      sudo zfs set $property=false $dataset
    fi

  done
 
  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  if [[ "$dry_run" == false ]]; then
    
    main

  fi

}

function remove_property() {

  local properties=()

  local properties=$(zfs get -o name,property,value -s local all -r | grep ':' | awk '{split($1, arr, "/"); print arr[1], $2}' | sort | uniq)

  if [[ -z $properties ]]; then

    echo "No custom properties found."
    echo ""
    return
  
  else

    echo "Custom Properties on All Pools:"
    echo ""

    local index=1
    local properties_array=()
    while IFS= read -r property; do
        properties_array+=("$index $property")
        ((index++))
    done <<< "$properties"

    for prop in "${properties_array[@]}"; do
      echo "$prop"
    done
    echo ""

  fi

  local selected_id=""
  while [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; do

    read -p "Enter the ID of the property to remove for a specific pool or (C)ancel: " selected_id
    echo ""

    if [[ "$selected_id" =~ ^[Cc]$  ]]; then
      echo "Operation canceled."
      echo ""
      show_menu
    fi

    if [[ ! "$selected_id" =~ ^[0-9]+$ || "$selected_id" -lt 1 || "$selected_id" -ge "$index" ]]; then
      echo "Invalid input. Please enter a valid ID or 'c' to cancel."
      echo ""
    fi

  done

  local property=""
  for prop in "${properties_array[@]}"; do
    if [[ "$prop" == "$selected_id "* ]]; then
      property=$(echo "$prop" | awk '{print $3}')
      pool=$(echo "$prop" | awk '{print $2}')
      break
    fi
  done

  echo "Remove Propery"
  echo "---------------------------------------------------------------------"

  echo ""
  echo "$pool" 
  echo "  |"
  echo "  '--> [$property]"
  echo "        Removing ..."

  # Extra check to ensure we are removing a custom property.
  if [[ "$dry_run" == false && "$property" == *":"* ]]; then
    sudo zfs inherit -r $property $pool
  fi

  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  main

}

function set_snapshot_permissions() {

  local -n items=$1

  local permissions_snapshot_and_send="compression,hold,release,send,snapshot"
  local permissions_snapshot_leaf="mount,destroy"

  echo "Setting Snapshot Permissions"
  echo "---------------------------------------------------------------------"

  for item in "${items[@]}"; do

    dataset=$(echo "$item" | awk '{print $2}')
    properties_string=$(echo "$item" | awk '{print $3}')

    echo ""
    echo "$dataset" 

    IFS=',' read -ra dataset_properties <<< "$properties_string"

    snapshot_enabled=false
    for property in "${dataset_properties[@]}"; do

      # Check if the property is not already in the properties array
      if [[ $property == "snapshot"* ]]; then

        property_value=$(zfs get -H -o value "$property" "$dataset")

        if [[ $property_value == "true" ]]; then

          snapshot_enabled=true

        fi

      fi

    done

    dataset_is_leaf=false
    if [[ $properties_string == *"snapshot-base"* ]]; then

      # Check if dataset has any children (if so we do not want to set destroy permissions)
      used_by_children=$(zfs get -H -o value -p usedbychildren $dataset)

      if [[ $used_by_children == 0 ]]; then

        dataset_is_leaf=true

      fi

    fi

    if [[ $snapshot_enabled == true ]]; then

      echo "  Snapshotting Enabled -> Allowing on Dataset + Descendents ($permissions_snapshot_and_send)..."

      if [[ "$dry_run" == false ]]; then
        sudo zfs allow -u $user $permissions_snapshot_and_send $dataset
      fi

      if [[ $dataset_is_leaf == true ]]; then

        echo "  Is Leaf Dataset -> Allowing on Descendents ($permissions_snapshot_leaf)..."

        if [[ "$dry_run" == false ]]; then
          sudo zfs allow -d -u $user $permissions_snapshot_leaf $dataset
        fi

      else

        echo "  Is Not Leaf Dataset -> Unallowing on Dataset (mount,destroy)..."

        if [[ "$dry_run" == false ]]; then
          sudo zfs unallow -d -u $user $permissions_snapshot_leaf $dataset
        fi

      fi

    else

      echo "  Snapshotting Disabled -> Unallowing on Dataset + Descendents ($permissions_snapshot_and_send + $permissions_snapshot_leaf)..."

      if [[ "$dry_run" == false ]]; then
        sudo zfs unallow -u $user $permissions_snapshot_and_send $dataset
        sudo zfs unallow -d -u $user $permissions_snapshot_leaf $dataset
      fi

    fi

  done
  
  echo ""

  if [[ "$dry_run" == false ]]; then
    
    main

  fi

} 

function remove_holds_delete_snapshots() {

  local -n items=$1
  local type="$2"
  local delete="$3"

  local heading="Releasing Holds"

  if [[ "$delete" == true ]]; then
    heading="Removing Snapshots"
  fi

  echo "$heading"
  echo "---------------------------------------------------------------------"

  # User chose to delete snapshots and release holds
  for item in "${items[@]}"; do

    dataset=$(echo "$item" | awk '{print $2}')
    echo ""
    echo "$dataset"

    if [[ "$type" == "snapshots" ]] ; then

      snapshots=$(echo "$item" | awk '{print $2 "@" $3}')

    else

      snapshots=$(zfs list -t snapshot -H -o name "$dataset")

      if [[ -z "$snapshots" ]]; then

        echo "  |"
        echo "  '--> No snapshots found..."
        
        continue

      fi

    fi
    

    while IFS= read -r snapshot; do

      echo "  |"
      echo "  '--> [$snapshot]"

      # Check if the snapshot has any hold tags
      holds=($(zfs holds -H "$snapshot" | awk '{ print $2 }'))

      if [ ${#holds[@]} -ne 0 ]; then

        for hold in "${holds[@]}"; do

          echo "          |"
          echo "          '--> [$hold]"

          echo "                Releasing ..."

          if [[ "$dry_run" == false ]]; then
            # Remove hold tags on the snapshot
            sudo zfs release -r "$hold" "$snapshot"
          fi

        done

      else

          echo "          |"
          echo "          '--> No holds found."      

      fi

      if [[ "$delete" == true ]]; then

        echo "        Destroying ..."

        # Added safety check to make sure this is actually a snapshot.
        if [[ "$dry_run" == false && $snapshot=*"@"* ]]; then
          
          sudo zfs destroy "$snapshot"
        fi

      fi

    done <<< "$snapshots"

  done

  echo ""
  echo "---------------------------------------------------------------------"
  echo ""

  if [[ "$dry_run" == false ]]; then
    
    main

  fi

}

function display_items() {

  local item_type="$1"
  local item_name="$2"
  local item_count="$3"
  local -n table_overview=$4
  local -n table_main=$5
  local -n table_headers=$6

  if [[ "$item_count" -lt 1 ]]; then

    echo "No $item_name found."
    show_menu
    return
  
  else

    local table_overview_local=("${table_overview[@]}")
    local table_main_local=("${table_main[@]}")
    local table_headers_local=("${table_headers[@]}")

    display_unique_table "$item_type" table_overview

    read -p "List $item_name by entering an ID ('m' for menu or 'q' to quit): " selected_index
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
      display_items "$item_type" "$item_name" "$item_count" table_overview_local table_main_local table_headers_local
      return
    fi

    # Get the selected item
    local selected_item=$(echo "${table_overview[selected_index]}" | awk '{print $2}')
    local count=$(echo "${table_overview[selected_index]}" | awk '{print $3}')

    display_list_table "$selected_item" "$item_name" "$count" table_headers table_main 

    display_items "$item_type" "$item_name" "$item_count" table_overview_local table_main_local table_headers_local

  fi

}

function change_top_dataset() {

  read -p "Enter the new top dataset name or hit enter for all ('m' for menu or 'q' to quit): " new_top_dataset
  echo ""

  # Check if the user wants to quit
  if [[ "$new_top_dataset" == "q" ]]; then
    exit 0
  fi

  # Check if the user wants to return to the menu
  if [[ "$new_top_dataset" == "m" ]]; then
    show_menu
    return
  fi

  if [ -n "$new_top_dataset" ] && ! zfs list -o name | grep -q "^$new_top_dataset$"; then

    echo "Dataset '$new_top_dataset' does not exist. Please enter a valid top dataset name."
    echo ""
    change_top_dataset
    return

  else

    top_dataset="$new_top_dataset"
    main

  fi

}

function show_menu() {

  echo "##########################################"
  echo "###        ZFS SNAPSHOT MANAGER        ###"
  echo "###              MAIN MENU             ###"
  echo "##########################################"
  echo "#                                        #"
  echo "#  Select an option:                     #"
  echo "#                                        #"
  echo "#  1. Show Summary / Totals              #"
  echo "#  2. List Datasets by Property          #"
  echo "#  3. List Snapshots by Name             #"
  echo "#  4. List Snapshots by Hold             #"
  echo "#  5. Add Property (Pool)                #"
  echo "#  6. Remove Property (Pool)             #"
  echo "#                                        #"
  echo "#  c. Change Top                         #" 
  echo "#  q. Quit                               #"
  echo "#                                        #"
  echo "##########################################"
  echo ""

  echo "User: $user"
  if [[ -z "$top_dataset" ]]; then
    echo -e "Selected Dataset: All Pool Roots"
  else
    echo -e "Selected Dataset: ${top_dataset}"
    echo -e "Root Dataset: ${root_dataset}"
    echo ""
    if [[ $include_parents == true ]]; then
      echo -e "Including Parent Datasets"
    else
      echo -e "Excluding Parent Datasets"
    fi
  fi
  echo ""

  if [[ "$dry_run" == true ]]; then
    echo -e "${GREEN}Script is in test mode ... no ZFS commands will be executed.${CLEAR}"
  else
    echo -e "${RED}Script is NOT in test mode .. ZFS commands will be executed."
    echo -e "Note that sudo password might be required for operations like 'destroy', 'create', 'snapshot' and 'set'.${CLEAR}"
  fi
  echo ""

  read -p "Enter your choice: " choice
  echo ""

  empty_array=()

  case "$choice" in
    1) display_summary ;;
    2) display_items "Properties" "datasets" "${datasets_with_property_count}" datasets_snapshot_property_table datasets_with_property_table datasets_table_headers;;
    3) display_items "Snapshots" "snapshots" "${datasets_with_snapshots_count}" dataset_snapshot_names_table dataset_snapshots_table dataset_snapshots_table_headers;;
    4) display_items "Holds" "snapshots" "${dataset_snapshots_with_hold_count}" dataset_snapshot_holds_table dataset_snapshots_table dataset_snapshots_table_headers;;
    5) add_property false empty_array;;
    6) remove_property ;;
    c) change_top_dataset ;;
    q) exit 0 ;;
    *) echo "Invalid option. Please try again."
       echo ""
       show_menu ;;
  esac
}

function main() {

  gather_snapshot_data
  show_menu

}

main