#!/usr/bin/env python3
"""
CesiumJS 3D Web Visualizer Generator for NADIR Constellations.
Packages CZML orbital ephemerides and laser crosslinks into standalone HTML viewer.
"""

import argparse
import sys
from pathlib import Path


def generate_cesium_html(czml_json_content: str, title: str = "NADIR Constellation Viewer") -> str:
    """Generates a self-contained HTML page embedding CesiumJS and the CZML document."""
    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <script src="https://cesium.com/downloads/cesiumjs/releases/1.114/Build/Cesium/Cesium.js"></script>
  <link href="https://cesium.com/downloads/cesiumjs/releases/1.114/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
  <style>
    html, body, #cesiumContainer {{
      width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background-color: #000;
    }}
    #hudPanel {{
      position: absolute; top: 16px; left: 16px; z-index: 999;
      background: rgba(15, 23, 42, 0.85); backdrop-filter: blur(8px);
      border: 1px solid rgba(56, 189, 248, 0.3); border-radius: 8px;
      padding: 14px 18px; color: #f8fafc; font-size: 13px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
    }}
    #hudPanel h1 {{
      margin: 0 0 6px 0; font-size: 15px; font-weight: 600;
      color: #38bdf8; letter-spacing: 0.5px;
    }}
    #hudPanel p {{ margin: 3px 0; color: #94a3b8; }}
    .badge {{
      display: inline-block; padding: 2px 6px; font-size: 11px;
      font-weight: 600; border-radius: 4px; background: rgba(56, 189, 248, 0.2);
      color: #38bdf8; margin-top: 4px;
    }}
  </style>
</head>
<body>
  <div id="cesiumContainer"></div>
  <div id="hudPanel">
    <h1>NADIR Mission Operations</h1>
    <p>Constellation: Autonomous Optical Mesh (Walker-Delta)</p>
    <p>Propagation: J2 Secular Perturbation Model</p>
    <div class="badge">LIVE 3D ORBIT TRACK</div>
  </div>

  <script>
    const czmlData = {czml_json_content};

    const viewer = new Cesium.Viewer('cesiumContainer', {{
      shouldAnimate: true,
      animation: true,
      timeline: true,
      baseLayerPicker: false,
      geocoder: false,
      homeButton: true,
      sceneModePicker: true,
      navigationHelpButton: false
    }});

    viewer.scene.globe.enableLighting = true;

    Cesium.CzmlDataSource.load(czmlData).then(function(dataSource) {{
      viewer.dataSources.add(dataSource);
      viewer.zoomTo(dataSource);
    }}).catch(function(error) {{
      console.error('Failed to load CZML constellation track:', error);
    }});
  </script>
</body>
</html>
"""
    return html_template


def main():
    parser = argparse.ArgumentParser(
        description="Generate CesiumJS 3D HTML browser visualizer from CZML file."
    )
    parser.add_argument("czml_file", type=str, help="Path to input .czml file")
    parser.add_argument("-o", "--output", type=str, default="", help="Output .html file path")

    args = parser.parse_args()
    czml_path = Path(args.czml_file)

    if not czml_path.exists():
        print(f"Error: CZML file not found: {czml_path}")
        sys.exit(1)

    with open(czml_path, "r", encoding="utf-8") as f:
        czml_text = f.read()

    html_content = generate_cesium_html(czml_text, title=f"NADIR - {czml_path.stem}")

    out_path = Path(args.output) if args.output else czml_path.with_suffix(".html")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"Generated standalone 3D visualizer: {out_path}")


if __name__ == "__main__":
    main()
