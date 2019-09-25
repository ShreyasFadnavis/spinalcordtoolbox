#!/usr/bin/env python
#
# Merge b=0 and dMRI data and output appropriate bvecs/bvals files.
#
# Copyright (c) 2019 Polytechnique Montreal <www.neuro.polymtl.ca>
# Author: Julien Cohen-Adad
#
# About the license: see the file LICENSE.TXT


from __future__ import absolute_import

import os
import sys
import argparse
import numpy as np

from dipy.data.fetcher import read_bvals_bvecs
from spinalcordtoolbox.utils import Metavar, SmartFormatter
from spinalcordtoolbox.image import Image, concat_data

import sct_utils as sct


def get_parser():
    parser = argparse.ArgumentParser(
        description="Concatenate b=0 scans with DWI time series and update the bvecs and bvals files.",
        formatter_class=SmartFormatter,
        add_help=None,
        prog=os.path.basename(__file__).strip(".py")
    )
    mandatory = parser.add_argument_group("\nMANDATORY ARGUMENTS")
    mandatory.add_argument(
        '-i',
        help="Input 4d files, separated by space, listed in the right order of concatenation. Example: b0.nii dmri1.nii dmri2.nii",
        nargs='+',
        metavar=Metavar.file,
        required=True,
    )
    mandatory.add_argument(
        '-bval',
        help="Bvals file(s). Example: bvals.txt",
        nargs='+',
        metavar=Metavar.file,
        required=True,
    )
    mandatory.add_argument(
        '-bvec',
        help="Bvecs file(s). Example: bvecs.txt",
        nargs='+',
        metavar=Metavar.file,
        required=True,
    )
    mandatory.add_argument(
        '-order',
        help="Order of b=0 and DWI files entered in flag '-i', separated by space. Example: b0 dwi dwi",
        nargs='+',
        choices=['b0', 'dwi'],
        metavar=Metavar.str,
        required=True,
    )
    mandatory.add_argument(
        '-o',
        help="Output 4d concatenated file. Example: b0_dmri_concat.nii",
        metavar=Metavar.file,
        required=True,
    )
    mandatory.add_argument(
        '-obval',
        help="Output concatenated bval file. Example: bval_concat.txt",
        metavar=Metavar.file,
        required=True,
    )
    mandatory.add_argument(
        '-obvec',
        help="Output concatenated bvec file. Example: bvec_concat.txt",
        metavar=Metavar.file,
        required=True,
    )
    optional = parser.add_argument_group("\nOPTIONAL ARGUMENTS")
    optional.add_argument(
        '-h',
        '--help',
        action='help',
        help="Show this help message and exit",
    )

    return parser


def main(args=None):
    """
    Main function
    :param args:
    :return:
    """
    # get parser args
    if args is None:
        args = None if sys.argv[1:] else ['--help']
    parser = get_parser()
    arguments = parser.parse_args(args=args)

    # check number of input args
    if not len(arguments.i) == len(arguments.order):
        raise Exception("Number of items between flags '-i' and '-order' should be the same.")
    if not len(arguments.bval) == len(arguments.bvec):
        raise Exception("Number of files for bval and bvec should be the same.")

    # Concatenate NIFTI files
    im_concat = concat_data(fname_in_list=arguments.i, dim=3, squeeze_data=False)
    im_concat.save(arguments.o)
    sct.printv("Generated file: {}".format(arguments.o))

    # Concatenate bvals and bvecs
    bvals_concat = ''
    bvecs_concat = ['', '', '']
    i_dwi = 0  # counter for DWI files, to read in bvec/bval files
    for i_item in range(len(arguments.order)):
        if arguments.order[i_item] == 'b0':
            # count number of b=0
            n_b0 = Image(arguments.i[i_item]).dim[3]
            bval = np.array([0.0] * n_b0)
            bvec = np.array([[0.0, 0.0, 0.0]] * n_b0)
        elif arguments.order[i_item] == 'dwi':
            # read bval/bvec files
            bval, bvec = read_bvals_bvecs(arguments.bval[i_dwi], arguments.bvec[i_dwi])
            i_dwi += 1
        # Concatenate bvals
        bvals_concat += ' '.join(str(v) for v in bval)
        bvals_concat += ' '
        # Concatenate bvecs
        for i in (0, 1, 2):
            bvecs_concat[i] += ' '.join(str(v) for v in map(lambda n: '%.16f' % n, bvec[:, i]))
            bvecs_concat[i] += ' '
    bvecs_concat = '\n'.join(str(v) for v in bvecs_concat)  # transform list into lines of strings
    # Write files
    new_f = open(arguments.obval, 'w')
    new_f.write(bvals_concat)
    new_f.close()
    sct.printv("Generated file: {}".format(arguments.obval))
    new_f = open(arguments.obvec, 'w')
    new_f.write(bvecs_concat)
    new_f.close()
    sct.printv("Generated file: {}".format(arguments.obvec))


if __name__ == "__main__":
    sct.init_sct()
    # call main function
    main()
