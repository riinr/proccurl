#!/usr/bin/env sh


# The objective is find what flags makes speed difference


mkdir bin

# Compile with some extension options
#
for X in \
  "mmmx"                \
  "mavx512vp2intersect" \
  "m3dnow"              \
  "m3dnowa"             \
  "mabm"                \
  "madx"                \
  "maes"                \
  "mamx-bf16"           \
  "mamx-complex"        \
  "mamx-fp16"           \
  "mamx-int8"           \
  "mamx-tile"           \
  "mapxf"               \
  "mavx"                \
  "mavx2"               \
  "mavx5124fmaps"       \
  "mavx5124vnniw"       \
  "mavx512bf16"         \
  "mavx512bitalg"       \
  "mavx512bw"           \
  "mavx512cd"           \
  "mavx512dq"           \
  "mavx512er"           \
  "mavx512f"            \
  "mavx512fp16"         \
  "mavx512ifma"         \
  "mavx512pf"           \
  "mavx512vbmi"         \
  "mavx512vbmi2"        \
  "mavx512vl"           \
  "mavx512vnni"         \
  "mavx512vpopcntdq"    \
  "mavxifma"            \
  "mavxneconvert"       \
  "mavxvnni"            \
  "mavxvnniint16"       \
  "mavxvnniint8"        \
  "mbmi"                \
  "mbmi2"               \
  "mcldemote"           \
  "mclflushopt"         \
  "mclwb"               \
  "mclzero"             \
  "mcmpccxadd"          \
  "menqcmd"             \
  "mf16c"               \
  "mfma"                \
  "mfma4"               \
  "mfsgsbase"           \
  "mfxsr"               \
  "mgfni"               \
  "mhle"                \
  "mhreset"             \
  "mkl"                 \
  "mlwp"                \
  "mlzcnt"              \
  "mmovdir64b"          \
  "mmovdiri"            \
  "mmwaitx"             \
  "mpclmul"             \
  "mpconfig"            \
  "mpku"                \
  "mpopcnt"             \
  "mprefetchi"          \
  "mprefetchwt1"        \
  "mprfchw"             \
  "mptwrite"            \
  "mraoint"             \
  "mrdpid"              \
  "mrdrnd"              \
  "mrdseed"             \
  "mrtm"                \
  "mserialize"          \
  "msgx"                \
  "msha"                \
  "msha512"             \
  "msm3"                \
  "msm4"                \
  "msse"                \
  "msse2"               \
  "msse3"               \
  "msse4"               \
  "msse4.1"             \
  "msse4.2"             \
  "msse4a"              \
  "mssse3"              \
  "mtbm"                \
  "mtsxldtrk"           \
  "muintr"              \
  "mvaes"               \
  "mvpclmulqdq"         \
  "mwaitpkg"            \
  "mwbnoinvd"           \
  "mwidekl"             \
  "mxop"                \
  "mxsave"              \
  "mxsavec"             \
  "mxsaveopt"           \
  "mxsaves"             \
  "muserms"
do
echo $X
nim c --threads:off -d:danger  -o:./bin/memcopy-$X --passC:"-$X" memcopy.nim
done
nim c --threads:off -d:danger  -o:./bin/memcopy-danger           memcopy.nim
nim c --threads:off -d:release -o:./bin/memcopy-release          memcopy.nim


# Compile with some architecture options
#

for X in \
  "native"      \
  "x86-64-v2"   \
  "x86-64-v3"   \
  "x86-64-v4"   \
  "nocona"      \
  "core2"       \
  "nehalem"     \
  "westmere"    \
  "sandybridge" \
  "ivybridge"   \
  "haswell"     \
  "broadwall"   \
  "skylake"     \
  "cannonlake"  \
  "cascadelake" \
  "cooperlake"  \
  "tigerlake"   \
  "alderlake"   \
  "rocketlake"  \
  "arrowlake"   \
  "pantherlake"
do
echo $X
nim c --threads:off -d:danger  -o:./bin/memcopy-$X --passC:"-march=$X" memcopy.nim
done

#  Results
#
#  Binary difference (sha256sum):
#  
#  c870419d97eac8d80d55499a02e67643fe1557c8400879ff3bb097b2a8a6f2da  ./memcopy-release
#
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx5124fmaps
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx5124vnniw
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512bitalg
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512cd
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512dq
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512er
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512f
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512ifma
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512pf
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512vbmi2
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512vnni
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512vp2intersect
#  a674be203feeca40279437074b6440949ae1a4a765c97da2d8e01bdd843e72d1  ./memcopy-mavx512vpopcntdq
#  
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-danger
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-m3dnow
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-m3dnowa
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mabm
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-madx
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-maes
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mamx-bf16
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mamx-int8
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mamx-tile
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mcldemote
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mclflushopt
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mclwb
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mclzero
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-menqcmd
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mfsgsbase
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mfxsr
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mgfni
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mhle
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mhreset
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mkl
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mlwp
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mlzcnt
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mmmx
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mmovdir64b
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mmovdiri
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mmwaitx
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mpclmul
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mpconfig
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mpku
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mpopcnt
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mprefetchwt1
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mprfchw
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mptwrite
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mrdpid
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mrdrnd
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mrdseed
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mrtm
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mserialize
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msgx
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msha
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse2
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse3
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse4
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse4.1
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse4.2
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-msse4a
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mssse3
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mtsxldtrk
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-muintr
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mvaes
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mvpclmulqdq
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mwaitpkg
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mwbnoinvd
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mwidekl
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mxsave
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mxsavec
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mxsaveopt
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-mxsaves
#  a6d2c9c423512c03dd9a6fb53de60d9a5512d1de51b2d5b744ab37a8ce1c99a1  ./memcopy-x86-64-v2
#  
#  bd958aedaa86c5250c974f22a241d6f75416a33fc0b6cbe801cbab9f1d83fe44  ./memcopy-mtbm
#  be275447eafcf4a0e90647e2329ec1e1bdd172d29f884f0805aa4e595cf72b4f  ./memcopy-mbmi2
#  c870419d97eac8d80d55499a02e67643fe1557c8400879ff3bb097b2a8a6f2da  ./memcopy-release
#  ce5bb329d55b2b1fa97b34bee52c7b3c99cf5af9b9d2ababf75bd98f98f4c484  ./memcopy-mavx512vl
#  d35d21fbaa88a3298dca4b0d7ddd090d34fcd7c59216c1bef3d8b938fb1ba07c  ./memcopy-skylake
#  d57eab3daa5798666883c1dde7818d573d4ff96ca217e2a23dd3810663bd6913  ./memcopy-nocona
#  db6bf3da4a674c3853f2a411acadcaa20dcb117310c382975ea9daf2976063c5  ./memcopy-x86-64-v3
#  
#  e043938386ce94d2daa495bb287f48d8bc81a50d04fc1d55adf91655ad3a21d8  ./memcopy-cannonlake
#  e043938386ce94d2daa495bb287f48d8bc81a50d04fc1d55adf91655ad3a21d8  ./memcopy-cascadelake
#  e043938386ce94d2daa495bb287f48d8bc81a50d04fc1d55adf91655ad3a21d8  ./memcopy-cooperlake
#  e043938386ce94d2daa495bb287f48d8bc81a50d04fc1d55adf91655ad3a21d8  ./memcopy-rocketlake
#  e043938386ce94d2daa495bb287f48d8bc81a50d04fc1d55adf91655ad3a21d8  ./memcopy-tigerlake
#  
#  f24e163831cb241dd3c1f0d2c7854d229613bcfd29c940a9f37a8f3a79b905e8  ./memcopy-nehalem
#  f24e163831cb241dd3c1f0d2c7854d229613bcfd29c940a9f37a8f3a79b905e8  ./memcopy-westmere
#  
#  2a827afa459a00d36e68945a3a51f174b900e210c20d1bfa98c40c2fb51d598a  ./memcopy-mavx512bf16
#  2a827afa459a00d36e68945a3a51f174b900e210c20d1bfa98c40c2fb51d598a  ./memcopy-mavx512bw
#  2a827afa459a00d36e68945a3a51f174b900e210c20d1bfa98c40c2fb51d598a  ./memcopy-mavx512fp16
#  2a827afa459a00d36e68945a3a51f174b900e210c20d1bfa98c40c2fb51d598a  ./memcopy-mavx512vbmi
#  
#  223ff5a8e9368de2f6c724291f8886d20a7dc47a8de389a8cedef2895c5e16c6  ./memcopy-mbmi
#
#  36b17f7ebaa3cff2884ecd0e7bbcc685c19c0b8c52cbfd7d5e32bdbae0ecf53c  ./memcopy-ivybridge
#  36b17f7ebaa3cff2884ecd0e7bbcc685c19c0b8c52cbfd7d5e32bdbae0ecf53c  ./memcopy-sandybridge
#  
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mavx
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mavx2
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mavxvnni
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mf16c
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mfma
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mfma4
#  4460a3bf2aded72919f7c3b7967ea1da64ad950b31a3eeee393ce4fa0a9811fa  ./memcopy-mxop
#
#  47f589db2e5f5c14d159d003aa53fdf9f8909429e41d21f34b96b59665484171  ./memcopy-alderlake
#  47f589db2e5f5c14d159d003aa53fdf9f8909429e41d21f34b96b59665484171  ./memcopy-native
#
#  5e391aa603cfe4d1ba60bc940b18041fbed330b2f9d11399f2c0db37c99d79b9  ./memcopy-haswell
#  8ce67f7f4c3e5ab61c913935165b49c855b1b560e543ebec2cb674a1a050ab9f  ./memcopy-x86-64-v4
#  95a0ab22e7645a02b19eb9dd63c20a7ba76a15c3bc9285ff947f90fb567fd21c  ./memcopy-core2
#
#
#  Binary difference (size in bytes):
#
#  142304 memcopy-m3dnow
#  142304 memcopy-m3dnowa
#  142304 memcopy-mmmx
#  142304 memcopy-mabm
#  142304 memcopy-madx
#  142304 memcopy-maes
#  142304 memcopy-mamx-bf16
#  142304 memcopy-mamx-int8
#  142304 memcopy-mamx-tile
#  142304 memcopy-mavx
#  142304 memcopy-mavx2
#  142304 memcopy-mavxvnni
#  142304 memcopy-mbmi
#  142304 memcopy-mbmi2
#  142304 memcopy-mcldemote
#  142304 memcopy-mclflushopt
#  142304 memcopy-mclwb
#  142304 memcopy-mclzero
#  142304 memcopy-menqcmd
#  142304 memcopy-mf16c
#  142304 memcopy-mfma
#  142304 memcopy-mfma4
#  142304 memcopy-mfsgsbase
#  142304 memcopy-mfxsr
#  142304 memcopy-mgfni
#  142304 memcopy-mhle
#  142304 memcopy-mhreset
#  142304 memcopy-mkl
#  142304 memcopy-mlwp
#  142304 memcopy-mlzcnt
#  142304 memcopy-mmovdir64b
#  142304 memcopy-mmovdiri
#  142304 memcopy-mmwaitx
#  142304 memcopy-mpclmul
#  142304 memcopy-mpconfig
#  142304 memcopy-mpku
#  142304 memcopy-mpopcnt
#  142304 memcopy-mprefetchwt1
#  142304 memcopy-mprfchw
#  142304 memcopy-mptwrite
#  142304 memcopy-mrdpid
#  142304 memcopy-mrdrnd
#  142304 memcopy-mrdseed
#  142304 memcopy-danger
#  142304 memcopy-mrtm
#  142304 memcopy-mserialize
#  142304 memcopy-msgx
#  142304 memcopy-msha
#  142304 memcopy-msse
#  142304 memcopy-msse2
#  142304 memcopy-msse3
#  142304 memcopy-msse4
#  142304 memcopy-msse4.1
#  142304 memcopy-msse4.2
#  142304 memcopy-msse4a
#  142304 memcopy-mssse3
#  142304 memcopy-mtsxldtrk
#  142304 memcopy-muintr
#  142304 memcopy-mvaes
#  142304 memcopy-mvpclmulqdq
#  142304 memcopy-mwaitpkg
#  142304 memcopy-mwbnoinvd
#  142304 memcopy-mwidekl
#  142304 memcopy-mxop
#  142304 memcopy-mxsave
#  142304 memcopy-mxsavec
#  142304 memcopy-mxsaveopt
#  142304 memcopy-mxsaves
#  142304 memcopy-alderlake
#  142304 memcopy-cannonlake
#  142304 memcopy-cascadelake
#  142304 memcopy-cooperlake
#  142304 memcopy-core2
#  142304 memcopy-haswell
#  142304 memcopy-ivybridge
#  142304 memcopy-native
#  142304 memcopy-nehalem
#  142304 memcopy-rocketlake
#  142304 memcopy-sandybridge
#  142304 memcopy-skylake
#  142304 memcopy-tigerlake
#  142304 memcopy-westmere
#  142304 memcopy-x86-64-v2
#  142304 memcopy-x86-64-v3
#  146400 memcopy-mavx512vp2intersect
#  146400 memcopy-mavx5124fmaps
#  146400 memcopy-mavx5124vnniw
#  146400 memcopy-mavx512bf16
#  146400 memcopy-mavx512bitalg
#  146400 memcopy-mavx512bw
#  146400 memcopy-mavx512cd
#  146400 memcopy-mavx512dq
#  146400 memcopy-mavx512er
#  146400 memcopy-mavx512f
#  146400 memcopy-mavx512fp16
#  146400 memcopy-mavx512ifma
#  146400 memcopy-mavx512pf
#  146400 memcopy-mavx512vbmi
#  146400 memcopy-mavx512vbmi2
#  146400 memcopy-mavx512vl
#  146400 memcopy-mavx512vnni
#  146400 memcopy-mavx512vpopcntdq
#  146400 memcopy-mtbm
#  146400 memcopy-x86-64-v4
#  150496 memcopy-nocona
#  165632 memcopy-release
#
#
#  Memcopy Speed (larger faster copy):
#
#  Ignoring:
#  - Those where sha256sum was the same
#  - Those that won't run in my machine (ie any avx)
#
#  Also see ./memcopy.sh
#
#  ./bin/memcopy-nehalem
#      550     1920 bytes
#      533     2048 bytes
#      694     7680 bytes
#      577     7936 bytes
#      775     8192 bytes
#
#  ./bin/memcopy-skylake
#      562     1920 bytes
#      599     2048 bytes
#      660     7680 bytes
#      732     7936 bytes
#      760     8192 bytes
#
#  ./bin/memcopy-danger
#      431     4096 bytes
#      412     7168 bytes
#     1066     7680 bytes
#     1319     7936 bytes
#     1197     8192 bytes
#
#  ./bin/memcopy-mbmi
#      403     4096 bytes
#      347     7168 bytes
#     1007     7680 bytes
#     1293     7936 bytes
#     1332     8192 bytes
#
#  ./bin/memcopy-mavx
#      353     4096 bytes
#      437     7168 bytes
#     1103     7680 bytes
#     1319     7936 bytes
#     1280     8192 bytes
#
#  ./bin/memcopy-mbmi2
#      469     4096 bytes
#      375     7168 bytes
#      956     7680 bytes
#     1257     7936 bytes
#     1310     8192 bytes
#
#  ./bin/memcopy-alderlake
#      494     1920 bytes
#      526     2048 bytes
#      755     7680 bytes
#      854     7936 bytes
#      726     8192 bytes
#
#  ./bin/memcopy-x86-64-v3
#      355     4096 bytes
#      419     7168 bytes
#     1122     7680 bytes
#     1344     7936 bytes
#     1219     8192 bytes
#
#  ./bin/memcopy-ivybridge
#      565     1920 bytes
#      536     2048 bytes
#      606     7680 bytes
#      815     7936 bytes
#      751     8192 bytes
#
#  ./bin/memcopy-haswell
#      556     1920 bytes
#      562     2048 bytes
#      514     7168 bytes
#      746     7680 bytes
#      768     8192 bytes
#
#  ./bin/memcopy-release
#      333     4096 bytes
#      412     7168 bytes
#      998     7680 bytes
#     1327     7936 bytes
#     1287     8192 bytes
#
#  ./bin/memcopy-core2
#      488     1920 bytes
#      558     2048 bytes
#      599     7680 bytes
#      829     7936 bytes
#     1079     8192 bytes
#
#  ./bin/memcopy-nocona
#      398     4096 bytes
#      650     7680 bytes
#     1171     7936 bytes
#     1494     8192 bytes
#      431    14336 bytes
