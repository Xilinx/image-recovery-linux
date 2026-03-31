# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

from setuptools import setup, find_packages
import os

# Read version from package
def get_version():
    version_file = os.path.join('src', 'image_recovery_cli', '__init__.py')
    if os.path.exists(version_file):
        with open(version_file, 'r') as f:
            for line in f:
                if line.startswith('__version__'):
                    return line.split('=')[1].strip().strip('"').strip("'")
    return '1.0.0'

setup(
    name='image-recovery',
    version=get_version(),
    description='AMD System Boot Image Recovery Tool',
    author='Raju Kumar Pothuraju',
    author_email='rajukumar.pothuraju@amd.com',
    license='MIT',
    packages=find_packages(where='src'),
    package_dir={'': 'src'},
    scripts=['bin/image-recovery-cli'],
    python_requires='>=3.6',
    install_requires=[],
    classifiers=[
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Operating System :: POSIX :: Linux',
    ],
)
