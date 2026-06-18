#!/usr/bin/env bash
# Creates a parser module with two existing parsers to mirror the style from.
cat > tmp_eval/parser.py <<'PY'
import json
import xml.etree.ElementTree as ET


def parse_json(text):
    """Parse a JSON string into a Python object."""
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON: {e}")


def parse_xml(text):
    """Parse an XML string into an ElementTree element."""
    try:
        return ET.fromstring(text)
    except ET.ParseError as e:
        raise ValueError(f"Invalid XML: {e}")
PY
