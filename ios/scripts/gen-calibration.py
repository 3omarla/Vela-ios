#!/usr/bin/env python3
"""Writes ios/Vela/Core/CalibrationDefaults.swift from the repo's calibration.json.

The iOS app compiles the same Google request templates, browser identity and result paths the
Android app ships. Run this after calibration.json changes: python3 ios/scripts/gen-calibration.py
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[2]
d = json.loads((root / "calibration.json").read_text())


def s(v):
    return json.dumps(v)


paths = "[" + ", ".join(f'"{k}": {s(v)}' for k, v in d["paths"].items()) + "]"
lines = [
    f"// Generated from Vela's calibration.json (version {d['version']}) by ios/scripts/gen-calibration.py. Do not edit.",
    "enum CalibrationDefaults {",
    f"    static let version = {d['version']}",
]
for key in ["userAgent", "secChUa", "searchEndpoint", "searchPb", "directionsEndpoint", "directionsPb",
            "sessionWarmUrl", "photosEndpoint", "photosProto"]:
    lines.append(f"    static let {key} = {s(d[key])}")
lines.append(f"    static let paths: [String: [Int]] = {paths}")
lines.append("}")
out = root / "ios" / "Vela" / "Core" / "CalibrationDefaults.swift"
out.write_text("\n".join(lines) + "\n")
print(f"wrote {out.relative_to(root)}")
