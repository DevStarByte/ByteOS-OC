return {
  name    = "tar",
  version = "1.1.1",
  rel     = 1,
  desc    = "pack files into ustar archives, list and unpack them (opens on a PC too)",
  depends = { "byteos>=1.16.0" },
  optdepends = { "gzip: tar -z for .tar.gz" },
}
