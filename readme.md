ZFS Snapshot Manager

Description:
This Bash script is made to help manage ZFS snapshots and custom dataset properties. It provides various options to list, select, and modify snapshots and properties of datasets in a ZFS pool.

Usage:
1. Make sure the script has execute permissions (`chmod +x zfs_snapshot_manager.sh`).
2. Run the script using `./zfs_snapshot_manager.sh`.
3. The script provides a menu-driven interface with the following options:
   - Show Summary / Totals: Display summary total counts for datasets and snapshots.
   - List Datasets by Property: List datasets based on a selected snapshot property.
   - List Snapshots by Name: List snapshots based on a selected snapshot name.
   - List Snapshots by Hold: List snapshots based on a selected hold tag.
   - Change Root: Change the root dataset for data collection.
   - Quit: Exit the script.
4. For each of the listing options the user can select all or a selection of the datasets/snapshots and perform actions on these.

Options:
- By default, the script will execute ZFS commands with elevated privileges (sudo) when required (e.g., for 'destroy', 'create', 'snapshot', and 'set' operations).
- The script supports a dry run mode ('-d' or '--dry-run') where no ZFS commands will be executed, allowing you to preview actions before applying them.

Note:
- The script assumes the user has sudo privileges to run ZFS commands.
- Please ensure that the root dataset provided with the `--root` option exists and is accessible.
- The script will exclude datasets with names containing any string in the variable `exclude_datasets` (used for instance to exclude datasets created by Docker).