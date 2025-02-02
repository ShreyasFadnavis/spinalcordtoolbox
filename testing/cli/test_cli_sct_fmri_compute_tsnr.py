import pytest
import logging

from spinalcordtoolbox.scripts import sct_fmri_compute_tsnr

logger = logging.getLogger(__name__)


@pytest.mark.sct_testing
@pytest.mark.usefixtures("run_in_sct_testing_data_dir")
def test_sct_sct_fmri_compute_tsnr_no_checks():
    """Run the CLI script without checking results.
    TODO: Check the results. (This test replaces the 'sct_testing' test, which did not implement any checks.)"""
    sct_fmri_compute_tsnr.main(argv=['-i', 'fmri/fmri.nii.gz', '-o', 'out_fmri_tsnr.nii.gz'])
