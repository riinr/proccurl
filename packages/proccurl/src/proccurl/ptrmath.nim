
proc `+`*[T](p: ptr T; i: int): ptr T =
  cast[ptr T](cast[int](p) + (sizeof(T) * i))

proc `-`*[T](p: ptr T; i: int): ptr T =
  cast[ptr T](cast[int](p) - (sizeof(T) * i))

proc `[]=`*[T](p: ptr T; i: int; v: sink T): void =
  let pp = p + i
  pp[] = v

proc `[]`*[T](p: ptr T; i: int): ptr T =
  p + i

