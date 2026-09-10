#!/usr/bin/env python3
"""
Deep analysis of .256 file structure to understand the actual format.
"""

import struct

def analyze_byte_patterns(filepath, max_bytes=2048):
    """Analyze byte patterns in .256 file."""
    with open(filepath, 'rb') as f:
        data = f.read(max_bytes)
    
    print(f"\n{'='*60}")
    print(f"File: {filepath}")
    print(f"Analyzing first {max_bytes} bytes\n")
    
    # Show as hex grid (16 bytes per row)
    print("Hex dump (first 256 bytes):")
    for i in range(0, min(256, len(data)), 16):
        hex_str = ' '.join(f'{b:02x}' for b in data[i:i+16])
        ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[i:i+16])
        print(f"  {i:04x}: {hex_str:<48s} {ascii_str}")
    
    # Look for repeating patterns
    print(f"\nSearching for patterns...")
    
    # Check for RLE-like patterns (count + value pairs)
    # Common RLE: [count][value] or [value][count]
    rle_candidates = []
    for i in range(len(data)-1):
        if data[i] == 0 and data[i+1] != 0:
            # Possible RLE: 00 XX (zero count followed by value)
            rle_candidates.append((i, 'zero_count', data[i+1]))
        elif data[i] != 0 and data[i+1] == 0:
            # Possible RLE: XX 00 (value followed by zero count)
            rle_candidates.append((i, 'value_zero', data[i]))
    
    if rle_candidates:
        print(f"  Found {len(rle_candidates)} potential RLE patterns")
        print(f"  Sample (first 10):")
        for pos, pattern_type, value in rle_candidates[:10]:
            print(f"    pos {pos:04x}: {pattern_type} value=0x{value:02x}")
    
    # Check for repeated sequences
    print(f"\nChecking for repeated sequences...")
    for seq_len in [4, 8, 16, 32, 64]:
        seq = data[:seq_len]
        count = 0
        for i in range(0, len(data)-seq_len, seq_len):
            if data[i:i+seq_len] == seq:
                count += 1
        if count > 2:
            print(f"  Sequence of {seq_len} bytes repeats {count} times")
    
    # Check if data has structure (every N bytes similar)
    print(f"\nByte value distribution (first 1024 bytes):")
    byte_counts = [0] * 256
    for b in data[:1024]:
        byte_counts[b] += 1
    
    # Show most common bytes
    sorted_bytes = sorted(range(256), key=lambda i: byte_counts[i], reverse=True)
    print(f"  Top 10 most common bytes:")
    for i in range(10):
        b = sorted_bytes[i]
        print(f"    0x{b:02x} ({b:3d}): {byte_counts[b]:4d} times ({byte_counts[b]/10.24:.1f}%)")
    
    # Check if it's compressed (high entropy = likely compressed)
    unique_bytes = sum(1 for c in byte_counts if c > 0)
    print(f"\n  Unique byte values: {unique_bytes}/256")
    if unique_bytes > 200:
        print(f"  -> High entropy, possibly compressed or raw pixel data")
    elif unique_bytes > 50:
        print(f"  -> Medium entropy, possibly structured data")
    else:
        print(f"  -> Low entropy, likely structured/compressed")

def main():
    # Test files
    test_files = [
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\units\monsters\orc\sprites.256",
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\structures\bhut1\house.256",
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\map-objects\bush1\sprites.256",
    ]
    
    for filepath in test_files:
        analyze_byte_patterns(filepath)

if __name__ == '__main__':
    main()
