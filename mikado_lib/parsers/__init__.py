#!/usr/bin/env python3
# coding: utf_8

"""
    This module defines the iterators that will parse BED12, GTF, GFF files.
"""

import io


class HeaderError(Exception):
    """
    Mock exception which is raised when a header/comment line (e.g. starting with "#") is found.
    """
    pass


class SizeError(Exception):
    """
    Custom exception
    """
    def __init__(self, value=None):
        self.value = value

    def __str__(self):
        return str(self.value)


class Parser(object):
    """Generic parser iterator. Base parser class."""

    def __init__(self, handle):
        self.__closed = False
        if not isinstance(handle, io.IOBase):
            try:
                handle = open(handle, "rt", buffering=1)
            except:
                raise TypeError
        self._handle = handle
        self.closed = False

    def __iter__(self):
        return self

    def __enter__(self):
        if self.closed is True:
            raise ValueError('I/O operation on closed file.')
        return self

    def __exit__(self, *args):
        _ = args
        self._handle.close()
        self.closed = True

    def close(self):
        """
        Alias for __exit__
        """
        self.__exit__()

    @property
    def name(self):
        """
        Return the filename.
        """
        return self._handle.name

    @property
    def closed(self):
        """
        Boolean flag. If True, the file has been closed already.
        """
        return self.__closed

    @closed.setter
    def closed(self, *args):
        """
        :param args: boolean flag

        This sets the closed flag of the file.

        """
        if type(args[0]) is not bool:
            raise TypeError("Invalid value: {0}".format(args[0]))

        self.__closed = args[0]


class TabParser(object):
    """Base class for iterating over tabular file formats."""

    def __init__(self, line: str):
        if not isinstance(line, str):
            raise TypeError
        if line == '':
            raise StopIteration

        self.line = line.rstrip()
        self._fields = self.line.split('\t')

    def __str__(self):
        return self.line

import mikado_lib.parsers.GFF
import mikado_lib.parsers.GTF
import mikado_lib.parsers.bed12
