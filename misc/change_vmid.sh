#!/usr/bin/env bash

# Script to change Proxmox VMID with verbose logging and color output
# Supports both VMs (QEMU) and Containers (LXC)
# License: MIT
# Author: Korper ICT

LOG_FILE="/var/log/proxmox_vmid_change.log"

# Color Codes
COLOR_RESET="\e[0m"
COLOR_INFO="\e[1;34m"
COLOR_ERROR="\e[1;31m"
COLOR_SUCCESS="\e[1;32m"
COLOR_SUMMARY="\e[1;33m"

# Verbose Logging Function
echo_verbose() {
    local message="${COLOR_INFO}[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1${COLOR_RESET}"
    echo -e "$message"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}
echo_error() {
    local message="${COLOR_ERROR}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1${COLOR_RESET}"
    echo -e "$message" >&2
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}
echo_success() {
    local message="${COLOR_SUCCESS}[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1${COLOR_RESET}"
    echo -e "$message"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}
echo_summary() {
    local message="${COLOR_SUMMARY}[SUMMARY] $(date '+%Y-%m-%d %H:%M:%S') $1${COLOR_RESET}"
    echo -e "$message"
    echo "[SUMMARY] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Function to Stop the VM or Container
stop_vm_ct() {
    echo_verbose "Stopping $TYPE with VMID $OLD_VMID..."
    if [[ $TYPE == "VM" ]]; then
        qm stop $OLD_VMID && echo_success "VM $OLD_VMID stopped successfully." || echo_error "Failed to stop VM $OLD_VMID."
    else
        pct stop $OLD_VMID && echo_success "Container $OLD_VMID stopped successfully." || echo_error "Failed to stop Container $OLD_VMID."
    fi
}

# Function to Rename Configuration File
rename_config() {
    echo_verbose "Renaming configuration file from $OLD_VMID to $NEW_VMID..."
    if [[ $TYPE == "VM" ]]; then
        if [[ -f /etc/pve/qemu-server/$OLD_VMID.conf ]]; then
            mv /etc/pve/qemu-server/$OLD_VMID.conf /etc/pve/qemu-server/$NEW_VMID.conf && \
            echo_success "Configuration file renamed: /etc/pve/qemu-server/$OLD_VMID.conf -> /etc/pve/qemu-server/$NEW_VMID.conf."
        else
            echo_error "Configuration file for VM $OLD_VMID not found at /etc/pve/qemu-server/$OLD_VMID.conf."
            exit 1
        fi
    else
        if [[ -f /etc/pve/lxc/$OLD_VMID.conf ]]; then
            mv /etc/pve/lxc/$OLD_VMID.conf /etc/pve/lxc/$NEW_VMID.conf && \
            echo_success "Configuration file renamed: /etc/pve/lxc/$OLD_VMID.conf -> /etc/pve/lxc/$NEW_VMID.conf."
        else
            echo_error "Configuration file for Container $OLD_VMID not found at /etc/pve/lxc/$OLD_VMID.conf."
            exit 1
        fi
    fi
}

# Function to Rename Storage Files
rename_storage() {
    echo_verbose "Renaming storage files for VMID $OLD_VMID..."
    if [[ $TYPE == "VM" ]]; then
        DISK_PATH="/var/lib/vz/images/$OLD_VMID"
        NEW_DISK_PATH="/var/lib/vz/images/$NEW_VMID"
        if [[ -d "$DISK_PATH" ]]; then
            mv "$DISK_PATH" "$NEW_DISK_PATH" && \
            echo_success "VM disk files renamed: $DISK_PATH -> $NEW_DISK_PATH."
        else
            echo_verbose "No disk files found at $DISK_PATH. Skipping storage rename."
        fi
    else
        CONTAINER_PATH="/var/lib/lxc/$OLD_VMID"
        NEW_CONTAINER_PATH="/var/lib/lxc/$NEW_VMID"
        if [[ -d "$CONTAINER_PATH" ]]; then
            mv "$CONTAINER_PATH" "$NEW_CONTAINER_PATH" && \
            echo_success "Container root filesystem renamed: $CONTAINER_PATH -> $NEW_CONTAINER_PATH."
        else
            echo_verbose "No root filesystem found at $CONTAINER_PATH. Skipping storage rename."
        fi
    fi
}

# Function to Verify Configuration
verify_config() {
    echo_verbose "Verifying configuration for VMID $NEW_VMID..."
    if [[ $TYPE == "VM" ]]; then
        qm config $NEW_VMID && echo_success "VM configuration verified successfully." || echo_error "Failed to verify VM configuration."
    else
        pct config $NEW_VMID && echo_success "Container configuration verified successfully." || echo_error "Failed to verify Container configuration."
    fi
}

# Function to Start VM or CT
start_vm_ct() {
    echo_verbose "Starting $TYPE with new VMID $NEW_VMID..."
    if [[ $TYPE == "VM" ]]; then
        qm start $NEW_VMID && echo_success "VM $NEW_VMID started successfully." || echo_error "Failed to start VM $NEW_VMID."
    else
        pct start $NEW_VMID && echo_success "Container $NEW_VMID started successfully." || echo_error "Failed to start Container $NEW_VMID."
    fi
}

# Function to List Available VMs or Containers
list_resources() {
    echo_verbose "Fetching available $1..."
    if [[ $1 == "VMs" ]]; then
        qm list | awk 'NR>1 {print $1, $2}' || echo_error "Failed to list VMs."
    else
        pct list | awk 'NR>1 {print $1, $3}' || echo_error "Failed to list Containers."
    fi
}

# Input Menu
echo -e "${COLOR_SUMMARY}Select the type of resource to change VMID:${COLOR_RESET}"
echo "1) Virtual Machine (QEMU)"
echo "2) Container (LXC)"
read -p "Enter your choice (1 or 2): " CHOICE

case $CHOICE in
    1)
        TYPE="VM"
        list_resources "VMs"
        ;;
    2)
        TYPE="CT"
        list_resources "Containers"
        ;;
    *)
        echo_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

read -p "Enter the current VMID: " OLD_VMID
read -p "Enter the new VMID: " NEW_VMID

if [[ -z "$OLD_VMID" || -z "$NEW_VMID" || ! "$OLD_VMID" =~ ^[0-9]+$ || ! "$NEW_VMID" =~ ^[0-9]+$ ]]; then
    echo_error "Both OLD_VMID and NEW_VMID must be numeric and specified. Exiting."
    exit 1
fi

# Confirm Selection
echo_verbose "You have selected to change $TYPE VMID from $OLD_VMID to $NEW_VMID."
read -p "Do you want to proceed? (yes/no): " CONFIRM
if [[ $CONFIRM != "yes" ]]; then
    echo_error "Operation canceled by user."
    exit 0
fi

# Main Process
echo_verbose "Starting VMID change process..."
stop_vm_ct
rename_config
rename_storage
verify_config
start_vm_ct

# Summary of Changes
echo_summary "Summary of Changes:"
echo_summary "- Stopped $TYPE with VMID $OLD_VMID."
echo_summary "- Configuration file renamed to /etc/pve/${TYPE,,}/$NEW_VMID.conf."
if [[ $TYPE == "VM" ]]; then
    echo_summary "- Storage files (if present) renamed to /var/lib/vz/images/$NEW_VMID."
else
    echo_summary "- Root filesystem (if present) renamed to /var/lib/lxc/$NEW_VMID."
fi
echo_summary "- Verified configuration for $NEW_VMID."
echo_summary "- Started $TYPE with new VMID $NEW_VMID."

echo_success "VMID change process completed successfully. New VMID: $NEW_VMID"
echo_verbose "Detailed logs have been saved to $LOG_FILE."
