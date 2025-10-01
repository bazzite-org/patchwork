#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright (C) 2025 Simone Caronni <negativo17@gmail.com>
# Copyright (C) 2025 Antheas Kapenekakis <negativo17@gmail.com>
# Licensed under the GNU General Public License Version or later

import argparse
import json
import re
import os
import shutil
import sys


def generate_pci_entries(gpu_list, open: bool = False):
    entries = []
    # Add GPU entries
    for gpu in gpu_list:
        for cls in ["PCI_CLASS_DISPLAY_VGA", "PCI_CLASS_DISPLAY_3D"]:
            # VGA controller entry
            entries.append(
                f"""    {{
            .vendor      = PCI_VENDOR_ID_NVIDIA,
            .device      = 0x{gpu},
            .subvendor   = PCI_ANY_ID,
            .subdevice   = PCI_ANY_ID,
            .class       = ({cls} << 8),
            .class_mask  = ~0
        }},"""
            )

    # Add NVSwitch entries
    for switch in devids_nvswitch:
        entries.append(
            f"""    {{
        .vendor      = PCI_VENDOR_ID_NVIDIA,
        .device      = 0x{switch},
        .subvendor   = PCI_ANY_ID,
        .subdevice   = PCI_ANY_ID,
        .class       = (PCI_CLASS_BRIDGE << 8),
        .class_mask  = ~0
    }},"""
        )

    # Add terminating empty entry
    entries.append("    { }")
    return entries


def patch_pci_table_file(header, filepath, gpu_list):
    with open(filepath, "r") as f:
        content = f.read()

    # Find and patch nv_pci_table
    table_pattern = r"struct pci_device_id nv_pci_table\[\] = \{(.*?)\};"
    match = re.search(table_pattern, content, re.DOTALL)
    if not match:
        print(f"Warning: Could not find nv_pci_table in {filepath}")
        return False

    # Generate new table entries
    new_entries = generate_pci_entries(gpu_list)
    new_table = (
        "struct pci_device_id nv_pci_table[] = {\n" + "\n".join(new_entries) + "\n};"
    )

    # Replace the old table with the new one
    content = re.sub(table_pattern, new_table, content, flags=re.DOTALL)

    # Find and patch nv_module_device_table
    module_table_pattern = (
        r"struct pci_device_id nv_module_device_table\[\d+\] = \{(.*?)\};"
    )
    module_header_pattern = (
        r"extern struct pci_device_id nv_module_device_table\[\d+\];"
    )
    match = re.search(module_table_pattern, content, re.DOTALL)
    if not match:
        print(f"Warning: Could not find nv_module_device_table in {filepath}")
        return False

    # Check if PCI_CLASS_BRIDGE_OTHER entry exists in the original
    bridge_other_pattern = r"{\s*\.vendor\s*=\s*PCI_VENDOR_ID_NVIDIA,\s*\.device\s*=\s*PCI_ANY_ID,\s*\.subvendor\s*=\s*PCI_ANY_ID,\s*\.subdevice\s*=\s*PCI_ANY_ID,\s*\.class\s*=\s*\(PCI_CLASS_BRIDGE_OTHER\s*<<\s*8\),\s*\.class_mask\s*=\s*~0\s*},"
    bridge_other_match = re.search(bridge_other_pattern, match.group(1), re.DOTALL)
    has_bridge_other = bridge_other_match is not None

    # Create the new module table entries
    module_entries = new_entries[:-1]  # Remove the terminator

    # Add properly formatted PCI_CLASS_BRIDGE_OTHER entry if it existed in original
    if has_bridge_other:
        bridge_other_entry = """    {
        .vendor      = PCI_VENDOR_ID_NVIDIA,
        .device      = PCI_ANY_ID,
        .subvendor   = PCI_ANY_ID,
        .subdevice   = PCI_ANY_ID,
        .class       = (PCI_CLASS_BRIDGE_OTHER << 8),
        .class_mask  = ~0
    },"""
        module_entries.append(bridge_other_entry)

    module_entries.append("    { }")  # Add back the terminator

    # Calculate the size needed for the module table
    table_size = len(module_entries)
    new_module_table = (
        f"struct pci_device_id nv_module_device_table[{table_size}] = {{\n"
        + "\n".join(module_entries)
        + "\n};"
    )
    new_module_header = (
        f"extern struct pci_device_id nv_module_device_table[{table_size}];"
    )

    # Replace the old module table with the new one
    content = re.sub(module_table_pattern, new_module_table, content, flags=re.DOTALL)

    # Write the modified content back to the file
    with open(filepath, "w") as f:
        f.write(content)

    # Ensure the header file has the extern declaration
    with open(header, "r") as f:
        header_content = f.read()

    header_content = re.sub(
        module_header_pattern, new_module_header, header_content, flags=re.DOTALL
    )

    with open(header, "w") as f:
        f.write(header_content)

    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Parse a supported-gpus.json file and patch PCI device table files."
    )
    parser.add_argument(
        "--json",
        dest="INPUT_JSON",
        help="The JSON file to be parsed (default: supported-gpus/supported-gpus.json)",
        type=str,
        default="supported-gpus/supported-gpus.json",
    )
    parser.add_argument(
        "--nvswitch",
        dest="NVSWITCH_C",
        help="The src/common/nvswitch/kernel/nvswitch.c file from the Open GPU kernel modules to parse for additional IDs",
        type=str,
    )
    parser.add_argument(
        "basedir",
        help="The base directory where the kernel and kernel-open folders are located",
        type=str,
        default=".",
    )
    args = parser.parse_args()

    b = args.basedir
    with open(os.path.join(b, args.INPUT_JSON), "r") as f:
        gpus_raw = json.load(f)

    devids_gpu_closed = []
    devids_gpu_open = []
    devids_nvswitch = []
    names = {}
    nvswitch_ids = {}

    for product in gpus_raw["chips"]:
        gpu = product["devid"].replace("0x", "")

        # For closed modules: exclude legacy branch and kernelopen GPUs
        if not ("legacybranch" in product or "kernelopen" in product["features"]):
            if not gpu in devids_gpu_closed:
                devids_gpu_closed.append(gpu)
                names[gpu] = product["name"]  # Store the GPU name

        # For open modules: include only kernelopen GPUs
        if "kernelopen" in product["features"]:
            if not gpu in devids_gpu_open:
                devids_gpu_open.append(gpu)
                names[gpu] = product["name"]  # Store the GPU name

    # Read and parse nvswitch.c for device IDs if provided
    if args.NVSWITCH_C:
        with open(os.path.join(b, args.NVSWITCH_C), "r") as f:
            nvswitch_content = f.read()

        # Pattern to match device ID arrays like: nvswitch_lr10_device_ids[] = { 0x1AE8, ... };
        id_patterns = re.finditer(
            r"nvswitch_(\w+)_device_ids\[\]\s*=\s*{([^}]+)}", nvswitch_content
        )
        for match in id_patterns:
            gen_name = match.group(1).upper()  # lr10 -> LR10
            # Extract hex numbers and convert to lowercase without 0x prefix
            ids = re.findall(r"0x([0-9A-Fa-f]+)", match.group(2))
            for device_id in ids:
                device_id = device_id.lower()
                devids_nvswitch.append(device_id)
                names[device_id] = f"NVIDIA NVSwitch {gen_name}"
                nvswitch_ids[device_id] = True

    # Patch kernel files with closed module GPUs
    driver_type = ["kernel", "kernel-open"]

    header_paths = [
        "nvidia/nv-pci-table.h",
        "nvidia-drm/nv-pci-table.h",
    ]
    list_paths = [
        "nvidia/nv-pci-table.c",
        "nvidia-drm/nv-pci-table.c",
    ]

    print(
        f"Found {len(devids_gpu_closed)} closed module GPUs and {len(devids_gpu_open)} open module GPUs"
    )

    for ktype in driver_type:
        for hname, cname in zip(header_paths, list_paths):
            hname = os.path.join(b, ktype, hname)
            cname = os.path.join(b, ktype, cname)

            for n in [hname, cname]:
                if os.path.exists(n + ".orig"):
                    shutil.copyfile(n + ".orig", n)
                elif os.path.exists(n):
                    shutil.copyfile(n, n + ".orig")
                else:
                    print(f"Error: Could not find {n}")
                    sys.exit(1)

            if ktype == "kernel":
                devs = devids_gpu_closed
                type_desc = "closed module"
            else:
                devs = devids_gpu_open
                type_desc = "open module"
            if patch_pci_table_file(hname, cname, devs):
                print(
                    f"-> Successfully patched {cname} with {len(devs)} {type_desc} GPUs"
                )
            else:
                print(f"Failed to patch {cname}")
                sys.exit(1)
