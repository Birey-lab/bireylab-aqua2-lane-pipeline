# README template for S3 backups
#
# Fill in the bracketed fields per dataset.
#
# Workflow:
#   1. Copy this template to a working file
#   2. Replace <bracketed placeholders> with real values
#   3. Save as README_<dataset>.txt (or README_<dataset>_CFU.txt for CFU)
#   4. Upload alongside the data:
#        aws s3 cp README_<dataset>.txt "s3://<bucket>/<prefix>/README.txt" --storage-class STANDARD
#
# Generate inline in PowerShell:
#   @"
#   ... (contents) ...
#   "@ | Set-Content C:\Users\Administrator\Documents\README_<dataset>.txt


<DATASET TITLE> Calcium Imaging - AQuA2 <Detection|CFU> Outputs
================================================================
N recordings: <N>  (<X> excluded - see below if applicable)
Magnification: <20x|10x|5x>  |  Donors: <list>  |  Conditions: <list>
Promoters (if applicable): <list>
Ages observed: <list of timepoints in days>
Tissue / preparation: <description>

ACQUISITION:
  Microscope: <model>
  Frame rate (nominal): <N> Hz
  Frame rate (measured): ~<value> Hz
  Recording duration: <N> frames (~<N> seconds)
  Spatial dimensions: <W> × <H> pixels

DETECTION PARAMETERS:
  maxSize     = <value> px  (active-region cap)
  minSize     = 20 px
  thrARScl    = 2
  minDur      = 3
  sourceSensitivity = 9
  detectGlo   = 1, gloDur = 20
  frameRate   = <value> s/frame
  spatialRes  = <value> um/px

CFU PARAMETERS (only for CFU README):
  overlapThr1/2 = 0.5
  minNumEvt1/2  = 3
  maxDist       = 10
  shift         = 0
  pValueThr     = 1e-5
  cfuNumThr     = 3

EXCLUDED FILES (if any):
  <stem>  -  <reason>
  <stem>  -  <reason>

nCFU DISTRIBUTION (only for CFU README):
  mean   <N>
  max    <N>
  min    <N>
  files with 0 CFUs: <N> (~<%>)

Cross-dataset comparability note (if applicable):
  Parameters identical to <other dataset>; comparisons valid.

Pipeline software:
  AQuA2 v<version>
  Compiled with: aqua_lane.exe + cfu_lane.exe (license-free, MATLAB Runtime)
  Pipeline version: <git tag or commit hash>

Source TIFFs: s3://<bucket>/CalciumImagingTIFFs/<path>/

Produced: YYYY-MM-DD
Run by: <name>
