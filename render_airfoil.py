import os
import sys
from paraview.simple import *

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
foam_file = os.path.join(ROOT_DIR, "cases", "airFoil2D", "airFoil2D.foam")
if not os.path.exists(foam_file):
    with open(foam_file, "w") as f:
        pass

reader = OpenFOAMReader(registrationName='airFoil2D.foam', FileName=foam_file)
reader.MeshRegions = ['internalMesh']
reader.CellArrays = ['p', 'U', 'nuTilda', 'nut']

animScene = GetAnimationScene()
animScene.UpdateAnimationUsingDataTimeSteps()
time_steps = reader.TimestepValues
if time_steps:
    animScene.AnimationTime = time_steps[-1]

renderView = GetActiveViewOrCreate('RenderView')
renderView.ViewSize = [1920, 1080]
renderView.Background = [0.08, 0.10, 0.14]

display = Show(reader, renderView, 'UniformGridRepresentation')
display.Representation = 'Surface'

# Color by Velocity Magnitude U
ColorBy(display, ('CELLS', 'U', 'Magnitude'))
uColorMap = GetColorTransferFunction('U')
uColorMap.ApplyPreset('Rainbow Desaturated', True)

# Zoom in on airfoil region (chord is ~35m, centered around x=0)
renderView.CameraPosition = [0.0, 0.0, 80.0]
renderView.CameraFocalPoint = [0.0, 0.0, 0.0]
renderView.CameraViewUp = [0, 1, 0]
renderView.CameraParallelProjection = 1
renderView.CameraParallelScale = 25.0

output_dir = os.path.join(ROOT_DIR, "renders_airfoil")
os.makedirs(output_dir, exist_ok=True)

# Render Velocity Field
SaveScreenshot(os.path.join(output_dir, "airfoil_velocity.png"), renderView, ImageResolution=[1920, 1080])

# Switch to Pressure Field
ColorBy(display, ('CELLS', 'p'))
pColorMap = GetColorTransferFunction('p')
pColorMap.ApplyPreset('Cool to Warm', True)

SaveScreenshot(os.path.join(output_dir, "airfoil_pressure.png"), renderView, ImageResolution=[1920, 1080])

print(f"Airfoil renders successfully saved to {output_dir} at Time={animScene.AnimationTime}")
