"""Compare DcmSwift's reading of DICOM files with pydicom's, through the
DICOM JSON Model (PS3.18 Annex F) that both produce.

  pydicom_json.py DCMPRINT [--pydicom-testdata] [PATH...]

DCMPRINT is the DcmPrint executable; PATHs are files or directories. Each
file is read by `DcmPrint -f JSON` and by pydicom's `Dataset.to_json_dict`;
the two objects are compared after normalization: numbers numerically,
strings without insignificant trailing spaces, binary values as bytes.
Prints one line per differing attribute and a summary; exits 1 on any
difference.
"""
import base64, json, math, os, subprocess, sys
import pydicom

def files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for name in sorted(names):
                    if not name.startswith('.'):
                        yield os.path.join(root, name)
        else:
            yield path

WORD = {'OW': 2, 'OF': 4, 'OL': 4, 'OD': 8, 'OV': 8}

def normalize(attribute, tag, big_endian=False):
    vr = attribute.get('vr')
    out = {'vr': vr}
    if 'InlineBinary' in attribute:
        data = base64.b64decode(attribute['InlineBinary'])
        # pydicom keeps the bytes of Big Endian files as stored; DcmSwift
        # writes Little Endian, which DICOMweb assumes.
        if big_endian and vr in WORD and len(data) % WORD[vr] == 0:
            size = WORD[vr]
            data = b''.join(data[i:i + size][::-1] for i in range(0, len(data), size))
        # Padding to even length is not significant in JSON (F.1).
        out['binary'] = data[:-1] if len(data) % 2 == 0 and data.endswith(b'\0') and vr != 'OB' else data
    if 'Value' in attribute:
        values = []
        for value in attribute['Value']:
            if vr == 'SQ':
                values.append(normalize_object(value, big_endian))
            elif vr == 'PN':
                values.append({k: v.rstrip() for k, v in (value or {}).items() if v} or None)
            elif isinstance(value, (int, float)) and not isinstance(value, bool):
                values.append(round(float(value), 6) if math.isfinite(value) else str(value))
            elif isinstance(value, str) and vr in ('DS', 'IS', 'FL', 'FD', 'SV', 'UV'):
                try:
                    values.append(round(float(value), 6))
                except ValueError:
                    values.append(value.strip())
            elif isinstance(value, str):
                values.append(value.rstrip(' \0') or None)
            else:
                values.append(value)
        while values and values[-1] is None and vr != 'SQ':
            values.pop()
        if values:
            out['Value'] = values
    return out

def normalize_object(obj, big_endian=False):
    return {tag.upper(): normalize(attr, tag, big_endian) for tag, attr in (obj or {}).items()
            if not tag.upper().endswith('0000')}

def compare(a, b, path=''):
    differences = []
    for tag in sorted(set(a) | set(b)):
        here = path + tag
        private = int(tag[3], 16) % 2 == 1
        if private and tag in a and tag in b and 'UN' in (a[tag]['vr'], b[tag]['vr']) and a[tag]['vr'] != b[tag]['vr']:
            # pydicom types private elements from its vendor dictionaries,
            # which DICOM does not define; DcmSwift keeps them UN.
            PRIVATE_UN[0] += 1
            continue
        if tag not in a:
            differences.append((here, 'only pydicom', b[tag]))
        elif tag not in b:
            differences.append((here, 'only DcmSwift', a[tag]))
        elif a[tag] != b[tag]:
            va, vb = a[tag].get('Value'), b[tag].get('Value')
            if a[tag]['vr'] == b[tag]['vr'] == 'SQ' and isinstance(va, list) and isinstance(vb, list) and len(va) == len(vb):
                for index, (ia, ib) in enumerate(zip(va, vb)):
                    differences += compare(ia, ib, '%s[%d].' % (here, index))
            else:
                differences.append((here, 'differs', (a[tag], b[tag])))
    return differences

PRIVATE_UN = [0]

def main():
    dcmprint, args = sys.argv[1], sys.argv[2:]
    paths = [a for a in args if not a.startswith('--')]
    if '--pydicom-testdata' in args:
        from pydicom.data import get_testdata_files
        paths += get_testdata_files('*.dcm')
    total = same = skipped = 0
    failures = []
    read_only_by_us = []
    for path in files(paths):
        try:
            ds = pydicom.dcmread(path)
            big_endian = getattr(ds.file_meta, 'TransferSyntaxUID', None) == '1.2.840.10008.1.2.2'
            reference = normalize_object(ds.to_json_dict(bulk_data_threshold=1 << 62), big_endian)
        except Exception as error:
            skipped += 1
            run = subprocess.run([dcmprint, '-f', 'JSON', path], capture_output=True)
            if run.returncode == 0 and run.stdout.strip().startswith(b'{'):
                read_only_by_us.append(path)
            continue
        total += 1
        run = subprocess.run([dcmprint, '-f', 'JSON', path], capture_output=True)
        if run.returncode != 0 or not run.stdout.strip():
            failures.append((path, [('', 'DcmSwift failed', run.stderr.decode(errors='replace')[-300:])]))
            continue
        try:
            ours = normalize_object(json.loads(run.stdout))
        except ValueError as error:
            failures.append((path, [('', 'invalid JSON', str(error))]))
            continue
        differences = compare(ours, reference)
        if differences:
            failures.append((path, differences))
        else:
            same += 1
    for path, differences in failures:
        print('==', path)
        for tag, kind, detail in differences[:12]:
            print('  ', tag, kind, str(detail)[:300])
        if len(differences) > 12:
            print('   ... %d more' % (len(differences) - 12))
    print('%d files compared, %d identical, %d different, %d unreadable by pydicom (%d of them read by DcmSwift); '
          '%d private elements typed only by pydicom' % (total, same, len(failures), skipped, len(read_only_by_us),
                                                         PRIVATE_UN[0]))
    sys.exit(1 if failures else 0)

main()
