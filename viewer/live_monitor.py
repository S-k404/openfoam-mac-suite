#!/usr/bin/env python3
"""
Real-Time OpenFOAM Live Convergence & Aerodynamics Dashboard
A standalone, zero-dependency local web app for monitoring OpenFOAM fluid simulations:
- Live residuals streaming (p, Ux, Uy, nuTilda, k, omega)
- Live aerodynamic force coefficients (Cl, Cd, Cm, L/D)
- Live flow field snapshot viewer (renders from pvpython)
- One-click macOS ParaView launch
"""

import http.server
import socketserver
import json
import os
import sys
import glob
import re
import subprocess
import urllib.parse
from datetime import datetime

PORT = 8080
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
CASES_DIR = os.path.join(PROJECT_ROOT, "cases")

def parse_solver_log(log_path):
    """Parse residuals and iteration data directly from solver log (e.g. log.simpleFoam)."""
    if not os.path.exists(log_path):
        return {"iterations": [], "residuals": {}, "status": "No log file found"}

    iterations = []
    residuals = {}
    current_time = None

    with open(log_path, "r", errors="ignore") as f:
        for line in f:
            t_match = re.match(r"^Time = (\d+(\.\d+)?)", line)
            if t_match:
                current_time = float(t_match.group(1))
                if current_time not in iterations:
                    iterations.append(current_time)
                continue

            r_match = re.search(r"Solving for (\w+), Initial residual = ([\d\.e\-\+]+)", line)
            if r_match and current_time is not None:
                field = r_match.group(1)
                res_val = float(r_match.group(2))
                if field not in residuals:
                    residuals[field] = []
                residuals[field].append({"time": current_time, "val": res_val})

    status = "Completed"
    with open(log_path, "r", errors="ignore") as f:
        content = f.read()
        if "converged in" in content:
            status = "Converged"
        elif "End" in content:
            status = "Completed"
        elif "FOAM FATAL" in content:
            status = "Error"
        else:
            status = "Running"

    return {"iterations": iterations[-200:], "residuals": residuals, "status": status}

def parse_force_coeffs(case_dir):
    """Parse force and moment coefficients from postProcessing/forceCoeffs."""
    candidates = glob.glob(os.path.join(case_dir, "postProcessing", "*force*", "*", "coefficient.dat"))
    if not candidates:
        return {"times": [], "cl": [], "cd": [], "cm": [], "ld": []}

    target = sorted(candidates)[-1]
    times, cl, cd, cm, ld = [], [], [], [], []

    try:
        with open(target, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= 8:
                    t = float(parts[0])
                    d_val = float(parts[1])
                    l_val = float(parts[4])
                    m_val = float(parts[7])
                    times.append(t)
                    cd.append(d_val)
                    cl.append(l_val)
                    cm.append(m_val)
                    ld.append(l_val / d_val if abs(d_val) > 1e-8 else 0.0)
    except Exception as e:
        print(f"Error parsing force coeffs: {e}")

    # Return last 200 points for smooth charting
    return {
        "times": times[-200:],
        "cl": cl[-200:],
        "cd": cd[-200:],
        "cm": cm[-200:],
        "ld": ld[-200:]
    }

def get_case_images(case_name):
    """Find rendered images for the case."""
    images = []
    # Check renders_airfoil
    if case_name == "airFoil2D":
        for p in glob.glob(os.path.join(PROJECT_ROOT, "renders_airfoil", "*.png")):
            images.append({
                "name": os.path.basename(p),
                "url": f"/api/image?path={urllib.parse.quote(p)}"
            })
    # Check frames_damBreak
    elif case_name == "damBreak":
        frames = sorted(glob.glob(os.path.join(PROJECT_ROOT, "frames_damBreak", "*.png")))
        if frames:
            images.append({
                "name": f"Latest Frame ({os.path.basename(frames[-1])})",
                "url": f"/api/image?path={urllib.parse.quote(frames[-1])}"
            })
    return images

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        if path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode("utf-8"))
            return

        elif path == "/api/cases":
            cases = [d for d in os.listdir(CASES_DIR) if os.path.isdir(os.path.join(CASES_DIR, d))]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"cases": sorted(cases)}).encode("utf-8"))
            return

        elif path == "/api/data":
            case_name = params.get("case", ["airFoil2D"])[0]
            case_dir = os.path.join(CASES_DIR, case_name)

            # Find log file
            log_files = glob.glob(os.path.join(case_dir, "log.*"))
            solver_log = log_files[0] if log_files else ""
            log_data = parse_solver_log(solver_log) if solver_log else {"iterations": [], "residuals": {}, "status": "No Log"}
            force_data = parse_force_coeffs(case_dir)
            images = get_case_images(case_name)

            response = {
                "case": case_name,
                "status": log_data["status"],
                "last_iteration": log_data["iterations"][-1] if log_data["iterations"] else 0,
                "residuals": log_data["residuals"],
                "forces": force_data,
                "images": images,
                "timestamp": datetime.now().strftime("%H:%M:%S")
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(response).encode("utf-8"))
            return

        elif path == "/api/image":
            img_path = params.get("path", [""])[0]
            if os.path.exists(img_path) and img_path.endswith(".png"):
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.end_headers()
                with open(img_path, "rb") as f:
                    self.wfile.write(f.read())
                return
            self.send_error(404, "Image not found")
            return

        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/api/paraview":
            case_name = params.get("case", ["airFoil2D"])[0]
            case_dir = os.path.join(CASES_DIR, case_name)
            parafoam_cmd = os.path.join(PROJECT_ROOT, "bin", "paraFoam")
            subprocess.Popen([parafoam_cmd, case_dir])

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "message": f"ParaView launched for {case_name}"}).encode("utf-8"))
            return

        elif parsed.path == "/api/render":
            case_name = params.get("case", ["airFoil2D"])[0]
            if case_name == "airFoil2D":
                pvpython = os.path.join(PROJECT_ROOT, "bin", "pvpython")
                render_script = os.path.join(PROJECT_ROOT, "render_airfoil.py")
                subprocess.Popen([pvpython, render_script])
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "message": "Render triggered"}).encode("utf-8"))
            return

        self.send_error(404)

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OpenFOAM Real-Time CFD Monitor</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    :root {
      --bg: #0b0f19;
      --card-bg: rgba(22, 30, 49, 0.8);
      --card-border: rgba(255, 255, 255, 0.08);
      --accent: #38bdf8;
      --accent-green: #34d399;
      --accent-orange: #fbbf24;
      --accent-red: #f87171;
      --text-main: #f1f5f9;
      --text-muted: #94a3b8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    body { background: var(--bg); color: var(--text-main); min-height: 100vh; padding: 24px; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--card-border); }
    .title-group { display: flex; align-items: center; gap: 12px; }
    .logo-badge { background: linear-gradient(135deg, #0284c7, #2563eb); padding: 8px 14px; border-radius: 8px; font-weight: 700; font-size: 16px; letter-spacing: 0.5px; }
    .controls { display: flex; gap: 12px; align-items: center; }
    select, button {
      background: var(--card-bg); color: var(--text-main); border: 1px solid var(--card-border);
      padding: 9px 16px; border-radius: 8px; font-size: 14px; font-weight: 600; cursor: pointer;
      transition: all 0.2s; backdrop-filter: blur(8px);
    }
    select:focus, button:hover { border-color: var(--accent); outline: none; }
    .btn-primary { background: linear-gradient(135deg, #0284c7, #0369a1); border: none; color: white; }
    .btn-primary:hover { opacity: 0.9; }

    .grid-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .card-stat { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 12px; padding: 18px; backdrop-filter: blur(10px); }
    .stat-label { font-size: 12px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.8px; margin-bottom: 6px; }
    .stat-value { font-size: 24px; font-weight: 700; color: var(--text-main); }
    .status-converged { color: var(--accent-green); }
    .status-running { color: var(--accent-orange); }

    .grid-charts { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 24px; }
    @media (max-width: 1024px) { .grid-charts { grid-template-columns: 1fr; } }
    .card-chart { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 12px; padding: 20px; backdrop-filter: blur(10px); }
    .chart-title { font-size: 16px; font-weight: 600; margin-bottom: 16px; color: var(--text-main); display: flex; justify-content: space-between; align-items: center; }

    .visual-gallery { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 12px; padding: 20px; }
    .gallery-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 16px; margin-top: 14px; }
    .gallery-item { border-radius: 8px; overflow: hidden; border: 1px solid var(--card-border); background: #000; }
    .gallery-item img { width: 100%; height: auto; display: block; }
    .gallery-item-title { padding: 10px 14px; font-size: 13px; color: var(--text-muted); background: rgba(0,0,0,0.6); }
  </style>
</head>
<body>

  <div class="header">
    <div class="title-group">
      <div class="logo-badge">OpenFOAM v2512</div>
      <h2>Real-Time CFD Fluid Simulation Monitor</h2>
    </div>
    <div class="controls">
      <label for="caseSelect" style="font-size:13px; color:var(--text-muted);">Active Case:</label>
      <select id="caseSelect" onchange="loadCase()"></select>
      <button class="btn-primary" onclick="launchParaView()">Open in macOS ParaView</button>
      <button onclick="triggerRender()">Render Slices</button>
    </div>
  </div>

  <div class="grid-stats">
    <div class="card-stat">
      <div class="stat-label">Solver State</div>
      <div class="stat-value" id="statusVal">-</div>
    </div>
    <div class="card-stat">
      <div class="stat-label">Iteration / Time Step</div>
      <div class="stat-value" id="iterVal">-</div>
    </div>
    <div class="card-stat">
      <div class="stat-label">Lift Coefficient (Cl)</div>
      <div class="stat-value" style="color:var(--accent-green)" id="clVal">-</div>
    </div>
    <div class="card-stat">
      <div class="stat-label">Drag Coefficient (Cd)</div>
      <div class="stat-value" style="color:var(--accent-orange)" id="cdVal">-</div>
    </div>
    <div class="card-stat">
      <div class="stat-label">Lift-to-Drag (L/D)</div>
      <div class="stat-value" style="color:var(--accent)" id="ldVal">-</div>
    </div>
  </div>

  <div class="grid-charts">
    <div class="card-chart">
      <div class="chart-title">
        <span>Solver Residuals (Logarithmic Convergence)</span>
        <span id="residualInfo" style="font-size:12px; color:var(--text-muted);">Live</span>
      </div>
      <canvas id="residualsChart" height="230"></canvas>
    </div>

    <div class="card-chart">
      <div class="chart-title">
        <span>Aerodynamic Coefficients Convergence (Cl, Cd, L/D)</span>
        <span id="forceInfo" style="font-size:12px; color:var(--text-muted);">Live</span>
      </div>
      <canvas id="forcesChart" height="230"></canvas>
    </div>
  </div>

  <div class="visual-gallery">
    <div class="chart-title">
      <span>Flow Field Visualizations (Rendered via Apple Silicon GPU/pvpython)</span>
      <span style="font-size:12px; color:var(--text-muted);">Auto-updating</span>
    </div>
    <div class="gallery-grid" id="galleryGrid">
      <p style="color:var(--text-muted); font-size:14px;">No visual frames available yet. Click "Render Slices" above.</p>
    </div>
  </div>

  <script>
    let resChart, forceChart;
    const colors = ['#38bdf8', '#34d399', '#fbbf24', '#f87171', '#a78bfa', '#fb923c'];

    function initCharts() {
      const resCtx = document.getElementById('residualsChart').getContext('2d');
      resChart = new Chart(resCtx, {
        type: 'line',
        data: { labels: [], datasets: [] },
        options: {
          responsive: true,
          animation: false,
          scales: {
            x: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#94a3b8' } },
            y: { type: 'logarithmic', grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#94a3b8' } }
          },
          plugins: { legend: { labels: { color: '#f1f5f9' } } }
        }
      });

      const forceCtx = document.getElementById('forcesChart').getContext('2d');
      forceChart = new Chart(forceCtx, {
        type: 'line',
        data: {
          labels: [],
          datasets: [
            { label: 'Lift (Cl)', borderColor: '#34d399', backgroundColor: 'transparent', data: [], borderWidth: 2 },
            { label: 'Drag (Cd)', borderColor: '#fbbf24', backgroundColor: 'transparent', data: [], borderWidth: 2 },
            { label: 'L/D Ratio', borderColor: '#38bdf8', backgroundColor: 'transparent', data: [], borderWidth: 2 }
          ]
        },
        options: {
          responsive: true,
          animation: false,
          scales: {
            x: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#94a3b8' } },
            y: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#94a3b8' } }
          },
          plugins: { legend: { labels: { color: '#f1f5f9' } } }
        }
      });
    }

    async function loadCases() {
      const res = await fetch('/api/cases');
      const data = await res.json();
      const select = document.getElementById('caseSelect');
      select.innerHTML = '';
      data.cases.forEach(c => {
        const opt = document.createElement('option');
        opt.value = c;
        opt.innerText = c;
        if (c === 'airFoil2D') opt.selected = true;
        select.appendChild(opt);
      });
      fetchData();
    }

    async function fetchData() {
      const activeCase = document.getElementById('caseSelect').value;
      if (!activeCase) return;

      try {
        const res = await fetch(`/api/data?case=${activeCase}`);
        const data = await res.json();

        // Update stats
        const statusEl = document.getElementById('statusVal');
        statusEl.innerText = data.status;
        statusEl.className = 'stat-value ' + (data.status === 'Converged' ? 'status-converged' : 'status-running');

        document.getElementById('iterVal').innerText = data.last_iteration || '0';

        if (data.forces.cl.length > 0) {
          const lastCl = data.forces.cl[data.forces.cl.length - 1];
          const lastCd = data.forces.cd[data.forces.cd.length - 1];
          const lastLd = data.forces.ld[data.forces.ld.length - 1];
          document.getElementById('clVal').innerText = lastCl.toFixed(4);
          document.getElementById('cdVal').innerText = lastCd.toFixed(4);
          document.getElementById('ldVal').innerText = lastLd.toFixed(2);
        }

        // Update Residuals Chart
        const fields = Object.keys(data.residuals);
        if (fields.length > 0) {
          const maxLens = Math.max(...fields.map(f => data.residuals[f].length));
          resChart.data.labels = Array.from({length: maxLens}, (_, i) => i + 1);
          resChart.data.datasets = fields.map((f, idx) => ({
            label: f,
            borderColor: colors[idx % colors.length],
            data: data.residuals[f].map(item => item.val),
            borderWidth: 1.5,
            pointRadius: 0
          }));
          resChart.update();
        }

        // Update Forces Chart
        if (data.forces.times.length > 0) {
          forceChart.data.labels = data.forces.times;
          forceChart.data.datasets[0].data = data.forces.cl;
          forceChart.data.datasets[1].data = data.forces.cd;
          forceChart.data.datasets[2].data = data.forces.ld;
          forceChart.update();
        }

        // Update Gallery
        const gallery = document.getElementById('galleryGrid');
        if (data.images.length > 0) {
          gallery.innerHTML = data.images.map(img => `
            <div class="gallery-item">
              <img src="${img.url}&t=${Date.now()}" alt="${img.name}">
              <div class="gallery-item-title">${img.name}</div>
            </div>
          `).join('');
        }
      } catch (err) {
        console.error('Fetch error:', err);
      }
    }

    function launchParaView() {
      const activeCase = document.getElementById('caseSelect').value;
      fetch(`/api/paraview?case=${activeCase}`, { method: 'POST' });
    }

    function triggerRender() {
      const activeCase = document.getElementById('caseSelect').value;
      fetch(`/api/render?case=${activeCase}`, { method: 'POST' });
      setTimeout(fetchData, 4000);
    }

    function loadCase() {
      fetchData();
    }

    initCharts();
    loadCases();
    setInterval(fetchData, 3000);
  </script>
</body>
</html>
"""

def main():
    os.chdir(PROJECT_ROOT)
    print("\n" + "=" * 65)
    print(f"  OpenFOAM Real-Time Web Monitor & CFD Dashboard")
    print(f"  URL: http://localhost:{PORT}")
    print(f"  Active Cases Directory: {CASES_DIR}")
    print("=" * 65 + "\n")

    # Auto-open in browser on macOS
    if sys.platform == "darwin":
        subprocess.Popen(["open", f"http://localhost:{PORT}"])

    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nDashboard server stopped.")

if __name__ == "__main__":
    main()
