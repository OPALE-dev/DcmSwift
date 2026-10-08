"""Check DcmSwift's Native DICOM Model XML (PS3.19 A.1).

  native_xml.py DCMPRINT [--pydicom-testdata] [PATH...]

For each file, `DcmPrint -f XML` must validate against the normative schema
(native-dicom-model.rnc, from DICOM 2026d) and, mapped to the DICOM JSON
Model as PS3.18 F.3 specifies, match pydicom's to_json_dict with the
normalization of pydicom_json.py. Needs rnc2rng and lxml.
"""
import os, subprocess, sys
import lxml.etree as etree
import rnc2rng
import pydicom

sys.path.insert(0, os.path.dirname(__file__))
import importlib.util
spec = importlib.util.spec_from_file_location('pj', os.path.join(os.path.dirname(__file__), 'pydicom_json.py'))
source = open(spec.origin).read().replace('\nmain()\n', '\n')
pj = {}
exec(compile(source, spec.origin, 'exec'), pj)

NS = '{http://dicom.nema.org/PS3.19/models/NativeDICOM}'
schema_path = os.path.join(os.path.dirname(__file__), 'native-dicom-model.rnc')
rng = rnc2rng.dumps(rnc2rng.load(schema_path))
schema = etree.RelaxNG(etree.fromstring(rng.encode()))

def to_json(node):
    """PS3.18 F.3: Native DICOM Model to DICOM JSON Model."""
    obj, blocks = {}, {}
    for attribute in node.findall(NS + 'DicomAttribute'):
        tag, vr = attribute.get('tag'), attribute.get('vr')
        creator = attribute.get('privateCreator')
        if creator is not None:
            group = tag[:4]
            used = blocks.setdefault(group, {})
            block = used.setdefault(creator, 0x10 + len(used))
            obj['%s%04X' % (group, block)] = {'vr': 'LO', 'Value': [creator]}
            tag = '%s%02X%s' % (group, block, tag[6:])
        out = {'vr': vr}
        bulk, inline = attribute.find(NS + 'BulkData'), attribute.find(NS + 'InlineBinary')
        if inline is not None:
            out['InlineBinary'] = inline.text or ''
        elif bulk is not None:
            out['BulkDataURI'] = bulk.get('uri')
        elif vr == 'SQ':
            items = attribute.findall(NS + 'Item')
            if items:
                out['Value'] = [to_json(item) for item in items]
        elif vr == 'PN':
            names = attribute.findall(NS + 'PersonName')
            if names:
                values = []
                for name in names:
                    value = {}
                    for group in ('Alphabetic', 'Ideographic', 'Phonetic'):
                        element = name.find(NS + group)
                        if element is not None:
                            parts = [(element.findtext(NS + c) or '') for c in
                                     ('FamilyName', 'GivenName', 'MiddleName', 'NamePrefix', 'NameSuffix')]
                            while parts and parts[-1] == '':
                                parts.pop()
                            value[group] = '^'.join(parts)
                    values.append(value or None)
                out['Value'] = values
        else:
            values = attribute.findall(NS + 'Value')
            if values:
                converted = []
                for value in values:
                    text = value.text
                    if text is None:
                        converted.append(None)
                    elif vr in ('US', 'SS', 'UL', 'SL', 'SV', 'UV', 'FL', 'FD', 'IS', 'DS'):
                        try:
                            converted.append(float(text))
                        except ValueError:
                            converted.append(text)
                    else:
                        converted.append(text)
                out['Value'] = converted
        obj[tag] = out
    return obj

def canonical(obj):
    """Private tags as group, creator, and element: blocks are reassigned
    by the mapping (F.3); trailing empty PN components are not significant
    (PS3.5 6.2.1) and cannot be written in XML."""
    out = {}
    for tag, attribute in obj.items():
        if attribute.get('vr') == 'SQ' and isinstance(attribute.get('Value'), list):
            attribute = dict(attribute, Value=[canonical(item) for item in attribute['Value']])
        if attribute.get('vr') == 'PN' and isinstance(attribute.get('Value'), list):
            names = [{k: v.rstrip('^') for k, v in (n or {}).items() if v.rstrip('^')} or None
                     for n in attribute['Value']]
            while names and names[-1] is None:
                names.pop()
            attribute = dict(attribute, Value=names) if names else {'vr': 'PN'}
        group, element = int(tag[:4], 16), int(tag[4:], 16)
        if group % 2 == 1 and 0x10 <= element <= 0xFF:
            continue
        if group % 2 == 1 and element >> 8 >= 0x10:
            creator = obj.get('%04X%04X' % (group, element >> 8), {}).get('Value', [''])[0]
            tag = '%04X:%s:%02X' % (group, creator, element & 0xFF)
        out[tag] = attribute
    return out

def main():
    dcmprint, args = sys.argv[1], sys.argv[2:]
    paths = [a for a in args if not a.startswith('--')]
    if '--pydicom-testdata' in args:
        from pydicom.data import get_testdata_files
        paths += get_testdata_files('*.dcm')
    total = valid = same = 0
    problems = []
    for path in pj['files'](paths):
        try:
            ds = pydicom.dcmread(path)
            big = getattr(ds.file_meta, 'TransferSyntaxUID', None) == '1.2.840.10008.1.2.2'
            reference = pj['normalize_object'](ds.to_json_dict(bulk_data_threshold=1 << 62), big)
        except Exception:
            continue
        run = subprocess.run([dcmprint, '-f', 'XML', path], capture_output=True)
        if run.returncode != 0:
            continue  # reading failures are reported by pydicom_json.py
        total += 1
        parser = etree.XMLParser(huge_tree=True)
        document = etree.fromstring(run.stdout, parser)
        # PS3.19 A.1.4 requires xml:space="preserve" on NativeDicomModel, but
        # the normative schema does not declare it: validate without it.
        checked = etree.fromstring(run.stdout, parser)
        checked.attrib.pop('{http://www.w3.org/XML/1998/namespace}space', None)
        if schema.validate(checked):
            valid += 1
        else:
            problems.append((path, 'schema', str(schema.error_log.last_error)))
            continue
        ours = canonical(pj['normalize_object'](to_json(document), False))
        differences = pj['compare'](ours, canonical(reference))
        if differences:
            problems.append((path, 'content', differences[:3]))
        else:
            same += 1
    for path, kind, detail in problems:
        print('==', path, kind, str(detail)[:400])
    print('%d files: %d valid against the PS3.19 schema, %d identical to pydicom through F.3; %d private elements '
          'typed only by pydicom' % (total, valid, same, pj['PRIVATE_UN'][0]))
    sys.exit(1 if problems else 0)

main()
