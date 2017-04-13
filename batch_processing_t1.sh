#!/bin/bash
#
# Example of commands to process multi-parametric data of the spinal cord
# For information about acquisition parameters, see: https://dl.dropboxusercontent.com/u/20592661/publications/Fonov_NIMG14_MNI-Poly-AMU.pdf
# N.B. The parameters are set for these type of data. With your data, parameters might be slightly different.
#
# To run without fslview output, type:
#   ./batch_processing.sh -nodisplay
#
# To prevent downloading sct_example_data and run from local folder, run:
#   ./batch_processing.sh -nodownload
#
# tested with Spinal Cord Toolbox (jca_newExampleData/2b72ae043690e5ecf017fbeb3b855dd288212849)

# Check if display is on or off
if [[ $@ == *"-nodisplay"* ]]; then
  DISPLAY=false
  echo "Display mode turned off."
else
  DISPLAY=true
fi

# Check if users wants to use his own data
if [[ $@ == *"-nodownload"* ]]; then
  echo "Use local folder."
else
  # download example data
  sct_download_data -d sct_example_data
  # go in folder
  cd sct_example_data
fi

# display starting time:
echo "Started at: $(date +%x_%r)"

# t1
# ===========================================================================================
cd t1
# Spinal cord segmentation
sct_propseg -i t1.nii.gz -c t1
# If segmentation leaks, you can try to smooth the cord and re-run the segmentation:
#sct_smooth_spinalcord -i t1.nii.gz -s t1_seg.nii.gz
#sct_propseg -i t1_smooth.nii.gz -c t1 -init-centerline t1_seg.nii.gz
#mv t1_smooth_seg.nii.gz t1_seg.nii.gz
# Check results:
if [ $DISPLAY = true ]; then
  fslview t1 -b 0,800 t1_seg -l Red -t 0.5 &
fi
# Vertebral labeling
sct_label_vertebrae -i t1.nii.gz -s t1_seg.nii.gz -c t1 -v 2
# Create labels at C2 and C5 vertebral levels
sct_label_utils -i t1_seg_labeled.nii.gz -vert-body 2,5
# Register to template
sct_register_to_template -i t1.nii.gz -s t1_seg.nii.gz -l labels.nii.gz -c t1
# Warp template without the white matter atlas (we don't need it at this point)
sct_warp_template -d t1.nii.gz -w warp_template2anat.nii.gz -a 0
# check results
if [ $DISPLAY = true ]; then
  fslview t1.nii.gz -b 0,800 label/template/PAM50_t1.nii.gz -b 0,4000 label/template/PAM50_levels.nii.gz -l MGH-Cortical -t 0.5 label/template/PAM50_gm.nii.gz -l Red-Yellow -b 0.5,1 label/template/PAM50_wm.nii.gz -l Blue-Lightblue -b 0.5,1 &
fi
# compute average cross-sectional area and volume between C3 and C4 levels
sct_process_segmentation -i t1_seg.nii.gz -p csa -vert 3:4
# go back to root folder
cd ..


# mt
# ----------
cd mt
# bring T1 segmentation in MT space to help segmentation (no optimization)
sct_register_multimodal -i ../t1/t1_seg.nii.gz -d mt1.nii.gz -identity 1 -x nn
# create mask for faster processing
sct_create_mask -i mt1.nii.gz -p centerline,t1_seg_reg.nii.gz -size 45mm
# crop data
sct_crop_image -i mt1.nii.gz -m mask_mt1.nii.gz -o mt1_crop.nii.gz
sct_crop_image -i mt0.nii.gz -m mask_mt1.nii.gz -o mt0_crop.nii.gz
# segment mt1
sct_propseg -i mt1_crop.nii.gz -c t2 -init-centerline t1_seg_reg.nii.gz
# Check results
if [ $DISPLAY = true ]; then
   fslview mt1_crop.nii.gz mt1_crop_seg.nii.gz -l Red -b 0,1 -t 0.7 &
fi
# Create close mask around spinal cord (for more accurate registration results)
sct_create_mask -i mt1_crop.nii.gz -p centerline,mt1_crop_seg.nii.gz -size 35mm -f cylinder
# Register mt0 on mt1
# Tips: here we only use rigid transformation because both images have very similar sequence parameters. We don't want to use SyN/BSplineSyN to avoid introducing spurious deformations.
sct_register_multimodal -i mt0_crop.nii.gz -d mt1_crop.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC -m mask_mt1_crop.nii.gz -x spline
# Check results
if [ $DISPLAY = true ]; then
   fslview mt1_crop.nii.gz mt0_crop_reg.nii.gz &
fi
# Compute mtr
sct_compute_mtr -mt0 mt0_crop_reg.nii.gz -mt1 mt1_crop.nii.gz
# Register template to mt1
# Tips: here we only use the segmentations due to poor SC/CSF contrast at the bottom slice.
# Tips: First step: slicereg based on images, with large smoothing to capture potential motion between anat and mt, then at second step: bpslinesyn in order to adapt the shape of the cord to the mt modality (in case there are distortions between anat and mt).
sct_register_multimodal -i $SCT_DIR/data/PAM50/template/PAM50_t2.nii.gz -d mt1_crop.nii.gz -iseg $SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz -dseg mt1_crop_seg.nii.gz -param step=1,type=seg,algo=slicereg,smooth=3:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -m mask_mt1_crop.nii.gz -initwarp ../t1/warp_template2anat.nii.gz
# Warp template (to get vertebral labeling)
sct_warp_template -d mt1_crop.nii.gz -w warp_PAM50_t22mt1_crop.nii.gz -a 0
# Segment gray matter
sct_segment_graymatter -i mt0_crop_reg.nii.gz -s mt1_crop_seg.nii.gz
# Register WM/GM template to WM/GM seg
sct_register_graymatter -gm mt0_crop_reg_gmseg.nii.gz -wm mt0_crop_reg_wmseg.nii.gz -w warp_PAM50_t22mt1_crop.nii.gz
# rename warping field for clarity
mv warp_PAM50_t22mt1_crop_reg_gm.nii.gz warp_template2mt.nii.gz
# warp template (this time corrected for internal structure)
sct_warp_template -d mt1_crop.nii.gz -w warp_template2mt.nii.gz
# Check registration result
if [ $DISPLAY = true ]; then
   fslview mt0_crop_reg.nii.gz label/template/PAM50_t2.nii.gz -b 0,4000 label/template/PAM50_levels.nii.gz -l MGH-Cortical -t 0.5 label/template/PAM50_gm.nii.gz -l Red-Yellow -b 0.5,1 label/template/PAM50_wm.nii.gz -l Blue-Lightblue -b 0.5,1 &
fi
# extract MTR within the white matter between C2 and C5
sct_extract_metric -i mtr.nii.gz -method map -o mtr_in_wm.txt -l 51 -vert 2:5
# Once we have register the WM atlas to the subject, we can compute the cross-sectional area (CSA) of the gray and white matter
sct_process_segmentation -i label/template/PAM50_wm.nii.gz -p csa -vert 2:5 -ofolder csa_wm
sct_process_segmentation -i label/template/PAM50_gm.nii.gz -p csa -vert 2:5 -ofolder csa_gm
cd ..


# dmri
# ----------
cd dmri
# bring T1 segmentation in dmri space to create mask (no optimization)
sct_maths -i dmri.nii.gz -mean t -o dmri_mean.nii.gz
sct_register_multimodal -i ../t1/t1_seg.nii.gz -d dmri_mean.nii.gz -identity 1 -x nn
# create mask to help moco and for faster processing
sct_create_mask -i dmri_mean.nii.gz -p centerline,t1_seg_reg.nii.gz -size 35mm
# crop data
sct_crop_image -i dmri.nii.gz -m mask_dmri_mean.nii.gz -o dmri_crop.nii.gz
# motion correction
sct_dmri_moco -i dmri_crop.nii.gz -bvec bvecs.txt
# segmentation with propseg
sct_propseg -i dwi_moco_mean.nii.gz -c t1 -init-centerline t1_seg_reg.nii.gz
# check segmentation
if [ $DISPLAY = true ]; then
  fslview dwi_moco_mean -b 0,1000 dwi_moco_mean_seg -l Red -t 0.5 &
fi
# Register template to dwi
# Tips: We use the template registered to the MT data in order to account for gray matter segmentation
# Tips: again, here, we prefer no stick to rigid registration on segmentation following by slicereg to realign center of mass. If there are susceptibility distortions in your EPI, then you might consider adding a third step with bsplinesyn or syn transformation for local adjustment.
sct_register_multimodal -i $SCT_DIR/data/PAM50/template/PAM50_t1.nii.gz -d dwi_moco_mean.nii.gz -iseg $SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz -dseg dwi_moco_mean_seg.nii.gz -param step=1,type=seg,algo=slicereg,smooth=5:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,smooth=1,iter=3 -initwarp ../mt/warp_template2mt.nii.gz
# rename warping field for clarity
mv warp_PAM50_t12dwi_moco_mean.nii.gz warp_template2dmri.nii.gz
# Warp template and white matter atlas
sct_warp_template -d dwi_moco_mean.nii.gz -w warp_template2dmri.nii.gz
# Visualize white matter template and lateral CST on DWI
if [ $DISPLAY = true ]; then
  fslview dwi_moco_mean -b 0,1000 label/template/PAM50_wm.nii.gz -l Blue-Lightblue -b 0.2,1 -t 0.5 label/atlas/PAM50_atlas_04.nii.gz -b 0.2,1 -l Red label/atlas/PAM50_atlas_05.nii.gz -b 0.2,1 -l Yellow &
fi
# Compute DTI metrics
# Tips: the flag -method "restore" allows you to estimate the tensor with robust fit (see help)
sct_dmri_compute_dti -i dmri_crop_moco.nii.gz -bval bvals.txt -bvec bvecs.txt
# Compute FA within right and left lateral corticospinal tracts from slices 2 to 14 using maximum a posteriori
sct_extract_metric -i dti_FA.nii.gz -z 2:14 -method wa -l 4,5 -o fa_in_cst.txt
cd ..


# display results (to easily compare integrity across SCT versions)
# ----------
echo "Ended at: $(date +%x_%r)"
echo
echo "t1/CSA:  " `grep -v '^#' t1/csa_mean.txt | grep -v '^$'`
echo "mt/MTR:  " `grep -v '^#' mt/mtr_in_wm.txt | grep -v '^$'`
echo "mt/CSA_GM:  " `grep -v '^#' mt/csa_gm/csa_mean.txt | grep -v '^$'`
echo "mt/CSA_WM:  " `grep -v '^#' mt/csa_wm/csa_mean.txt | grep -v '^$'`
echo "dmri/FA: " `grep -v '^#' dmri/fa_in_cst.txt | grep -v 'right'`
echo "dmri/FA: " `grep -v '^#' dmri/fa_in_cst.txt | grep -v 'left'`
echo