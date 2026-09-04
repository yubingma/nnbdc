import os
import struct
import subprocess
import shutil

def patch_single_macho(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())
    if len(data) < 32:
        return False
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic != 0xfeedfacf:
        return False
    ncmds, sizeofcmds = struct.unpack_from('<II', data, 16)
    offset = 32
    patched = False
    for _ in range(ncmds):
        if offset + 12 > len(data):
            break
        cmd, cmdsize = struct.unpack_from('<II', data, offset)
        if cmd == 0x32: # LC_BUILD_VERSION
            platform = struct.unpack_from('<I', data, offset + 8)[0]
            if platform in (1, 2): # PLATFORM_IOS
                struct.pack_into('<I', data, offset + 8, 7) # PLATFORM_IOSSIMULATOR
                patched = True
        offset += cmdsize
    if patched:
        with open(path, 'wb') as f:
            f.write(data)
    return patched

def patch_ar_archive(data):
    if not data.startswith(b'!<arch>\n'):
        return 0
    pos = 8
    count = 0
    while pos < len(data):
        if pos + 60 > len(data):
            break
        header = data[pos:pos+60]
        try:
            size = int(header[48:58].strip())
        except ValueError:
            break
        namelen = 0
        name = header[:16].strip()
        if name.startswith(b'#1/'):
            namelen = int(name[3:])
        
        member_start = pos + 60 + namelen
        member_size = size - namelen
        member_end = pos + 60 + size
        
        member_data = memoryview(data)[member_start:member_end]
        if len(member_data) >= 32:
            magic = struct.unpack_from('<I', member_data, 0)[0]
            if magic == 0xfeedfacf:
                ncmds, sizeofcmds = struct.unpack_from('<II', member_data, 16)
                offset = 32
                for _ in range(ncmds):
                    if offset + 12 > len(member_data):
                        break
                    cmd, cmdsize = struct.unpack_from('<II', member_data, offset)
                    if cmd == 0x32:
                        platform = struct.unpack_from('<I', member_data, offset + 8)[0]
                        if platform in (1, 2):
                            struct.pack_into('<I', data, member_start + offset + 8, 7)
                            count += 1
                    offset += cmdsize
        pos = member_end + (member_end % 2)
    return count

def patch_framework(fw_rel_path, base_dir):
    full_path = os.path.join(base_dir, fw_rel_path)
    if not os.path.exists(full_path):
        return
    
    orig_path = full_path + '.orig'
    if not os.path.exists(orig_path):
        shutil.copyfile(full_path, orig_path)
    
    tmp_arm64 = '/tmp/_patch_arm64.bin'
    tmp_x86 = '/tmp/_patch_x86.bin'
    
    try:
        subprocess.run(['lipo', '-thin', 'arm64', orig_path, '-output', tmp_arm64], check=True, stderr=subprocess.DEVNULL)
        has_x86 = subprocess.run(['lipo', '-thin', 'x86_64', orig_path, '-output', tmp_x86], stderr=subprocess.DEVNULL).returncode == 0
    except Exception:
        return
    
    # 尝试作为单个 mach-o
    patched = patch_single_macho(tmp_arm64)
    if not patched:
        # 尝试作为 ar archive
        with open(tmp_arm64, 'rb') as f:
            d = bytearray(f.read())
        c = patch_ar_archive(d)
        if c > 0:
            with open(tmp_arm64, 'wb') as f:
                f.write(d)
            patched = True
            
    if patched:
        if has_x86:
            subprocess.run(['lipo', '-create', tmp_arm64, tmp_x86, '-output', full_path], check=True)
        else:
            shutil.copyfile(tmp_arm64, full_path)
        print(f'✅ Successfully enabled Apple Silicon simulator support for {os.path.basename(fw_rel_path)}')

if __name__ == '__main__':
    base = os.path.dirname(os.path.abspath(__file__))
    targets = [
        'Pods/MLKitCommon/Frameworks/MLKitCommon.framework/MLKitCommon',
        'Pods/MLKitDigitalInkRecognition/Frameworks/MLKitDigitalInkRecognition.framework/MLKitDigitalInkRecognition',
        'Pods/MLKitMDD/Frameworks/MLKitMDD.framework/MLKitMDD'
    ]
    for t in targets:
        patch_framework(t, base)
