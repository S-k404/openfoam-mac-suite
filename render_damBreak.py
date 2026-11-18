import os
import sys
from paraview.simple import *

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
foam_file = os.path.join(ROOT_DIR, "cases", "damBreak", "damBreak.foam")
reader = OpenFOAMReader(registrationName='damBreak.foam', FileName=foam_file)
reader.MeshRegions = ['internalMesh']
reader.CellArrays = ['alpha.water', 'U', 'p_rgh']

renderView = GetActiveViewOrCreate('RenderView')
renderView.ViewSize = [1280, 720]
renderView.Background = [0.12, 0.14, 0.18]

display = Show(reader, renderView, 'UniformGridRepresentation')
display.Representation = 'Surface'

# Color by alpha.water
ColorBy(display, ('CELLS', 'alpha.water'))
colorMap = GetColorTransferFunction('alphawater')
colorMap.ApplyPreset('Cool to Warm', True)

# Set camera to front 2D view (+Z normal)
renderView.CameraPosition = [0.292, 0.292, 1.2]
renderView.CameraFocalPoint = [0.292, 0.292, 0.0]
renderView.CameraViewUp = [0, 1, 0]
renderView.CameraParallelProjection = 1
renderView.CameraParallelScale = 0.32

output_dir = os.path.join(ROOT_DIR, "frames_damBreak")
os.makedirs(output_dir, exist_ok=True)

animScene = GetAnimationScene()
animScene.UpdateAnimationUsingDataTimeSteps()

SaveAnimation(
    os.path.join(output_dir, "frame.png"),
    viewOrLayout=renderView,
    ImageResolution=[1280, 720],
    FrameRate=10
)
print("Rendering complete!")
