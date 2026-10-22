#!/usr/bin/perl
# Загружает libIslandMedia.dylib в системный perl и передаёт ей управление.
use strict;
use DynaLoader;

my $path = shift or die "usage: run.pl <libIslandMedia.dylib>\n";
my $lib = DynaLoader::dl_load_file($path, 0) or die "dl_load_file: " . DynaLoader::dl_error() . "\n";
my $sym = DynaLoader::dl_find_symbol($lib, "island_media_stream") or die "symbol not found\n";
DynaLoader::dl_install_xsub("main::island_media_stream", $sym);
island_media_stream();
