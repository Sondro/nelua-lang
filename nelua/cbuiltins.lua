--[[
C builtins.

This module defines implementations for many builtin C functions used by the C code generator.
]]

local pegger = require 'nelua.utils.pegger'
local bn = require 'nelua.utils.bn'
local cdefs = require 'nelua.cdefs'
local CEmitter = require 'nelua.cemitter'
local typedefs = require 'nelua.typedefs'
local primtypes = typedefs.primtypes

-- The cbuiltins table.
local cbuiltins = {}

do -- Define builtins from C headers.
  for name, header in pairs(cdefs.builtins_headers) do
    cbuiltins[name] = function(context)
      context:ensure_include(header)
    end
  end
end

-- Used by `likely` builtin.
function cbuiltins.nelua_likely(context)
  context:define_builtin_macro('nelua_likely', [[
/* Macro used for branch prediction. */
#if defined(__GNUC__) || defined(__clang__)
  #define nelua_likely(x) __builtin_expect(x, 1)
#else
  #define nelua_likely(x) (x)
#endif
]], 'directives')
end

-- Used by `unlikely` builtin.
function cbuiltins.nelua_unlikely(context)
  context:define_builtin_macro('nelua_unlikely', [[
/* Macro used for branch prediction. */
#if defined(__GNUC__) || defined(__clang__)
  #define nelua_unlikely(x) __builtin_expect(x, 0)
#else
  #define nelua_unlikely(x) (x)
#endif
]], 'directives')
end

-- Used by import and export builtins.
function cbuiltins.nelua_extern(context)
  context:define_builtin_macro('nelua_extern', [[
/* Macro used to import/export extern C functions. */
#ifdef __cplusplus
  #define nelua_extern extern "C"
#else
  #define nelua_extern extern
#endif
]], 'directives')
end

-- Used by `<cexport>`.
function cbuiltins.nelua_cexport(context)
  context:ensure_builtin('nelua_extern')
  context:define_builtin_macro('nelua_cexport', [[
/* Macro used to export C functions. */
#ifdef _WIN32
  #define nelua_cexport nelua_extern __declspec(dllexport)
#elif defined(__GNUC__)
  #define nelua_cexport nelua_extern __attribute__((visibility("default")))
#else
  #define nelua_cexport nelua_extern
#endif
]], 'directives')
end

-- Used by `<cimport>` without `<nodecl>`.
function cbuiltins.nelua_cimport(context)
  context:ensure_builtin('nelua_extern')
  context:define_builtin_macro('nelua_cimport', [[
/* Macro used to import C functions. */
#define nelua_cimport nelua_extern
]], 'directives')
end

-- Used by `<noinline>`.
function cbuiltins.nelua_noinline(context)
  context:define_builtin_macro('nelua_noinline', [[
/* Macro used to force not inlining a function. */
#ifdef __GNUC__
  #define nelua_noinline __attribute__((noinline))
#elif defined(_MSC_VER)
  #define nelua_noinline __declspec(noinline)
#else
  #define nelua_noinline
#endif
]], 'directives')
end

-- Used by `<inline>`.
function cbuiltins.nelua_inline(context)
  context:define_builtin_macro('nelua_inline', [[
/* Macro used to force inlining a function. */
#ifdef __GNUC__
  #define nelua_inline __attribute__((always_inline)) inline
#elif defined(_MSC_VER)
  #define nelua_noinline __forceinline
#elif __STDC_VERSION__ >= 199901L
  #define nelua_inline inline
#else
  #define nelua_inline
#endif
]], 'directives')
end

-- Used by `<register>`.
function cbuiltins.nelua_register(context)
  context:define_builtin_macro('nelua_register', [[
/* Macro used to hint a variable to use a register. */
#ifdef __STDC_VERSION__
  #define nelua_register register
#else
  #define nelua_register
#endif
]], 'directives')
end

-- Used by `<noreturn>`.
function cbuiltins.nelua_noreturn(context)
  context:define_builtin_macro('nelua_noreturn', [[
/* Macro used to specify a function that never returns. */
#if __STDC_VERSION__ >= 201112L
  #define nelua_noreturn _Noreturn
#elif defined(__GNUC__)
  #define nelua_noreturn __attribute__((noreturn))
#elif defined(_MSC_VER)
  #define nelua_noreturn __declspec(noreturn)
#else
  #define nelua_noreturn
#endif
]], 'directives')
end

-- Used by `<atomic>`.
function cbuiltins.nelua_atomic(context)
  context:define_builtin_macro('nelua_atomic', [[
/* Macro used to declare atomic types. */
#if __STDC_VERSION__ >= 201112L && !defined(__STDC_NO_ATOMICS__)
  #define nelua_atomic _Atomic
#elif __cplusplus >= 201103L
  #include <atomic>
  #define nelua_atomic(T) std::atomic<T>
#else
  #define nelua_atomic(a) a
  #error "Atomic is unsupported."
#endif
]], 'directives')
end

-- Used by `<threadlocal>`.
function cbuiltins.nelua_threadlocal(context)
  context:define_builtin_macro('nelua_threadlocal', [[
/* Macro used to specify a alignment for structs. */
#if __STDC_VERSION__ >= 201112L && !defined(__STDC_NO_THREADS__)
  #define nelua_threadlocal _Thread_local
#elif __cplusplus >= 201103L
  #define nelua_threadlocal thread_local
#elif defined(__GNUC__)
  #define nelua_threadlocal __thread
#elif defined(_MSC_VER)
  #define nelua_threadlocal __declspec(thread)
#else
  #define nelua_threadlocal
  #error "Thread local is unsupported."
#endif
]], 'directives')
end

-- Used by `<packed>` on type declarations.
function cbuiltins.nelua_packed(context)
  context:define_builtin_macro('nelua_packed', [[
/* Macro used to specify a struct alignment. */
#if defined(__GNUC__) || defined(__clang__)
  #define nelua_packed __attribute__((packed))
#else
  #define nelua_packed
#endif
]], 'directives')
end

-- Used by `<aligned>` on type declarations.
function cbuiltins.nelua_aligned(context)
  context:define_builtin_macro('nelua_aligned', [[
/* Macro used to specify a alignment for structs. */
#if defined(__GNUC__)
  #define nelua_aligned(X) __attribute__((aligned(X)))
#elif defined(_MSC_VER)
  #define nelua_aligned(X) __declspec(align(X))
#else
  #define nelua_aligned(X)
#endif
]], 'directives')
end

-- Used by `<aligned>` on variable declarations.
function cbuiltins.nelua_alignas(context)
  context:define_builtin_macro('nelua_alignas', [[
/* Macro used set alignment for a type. */
#if __STDC_VERSION__ >= 201112L
  #define nelua_alignas(X) _Alignas(X)
#elif __cplusplus >= 201103L
  #define nelua_alignas(X) alignas(X)
#elif defined(__GNUC__)
  #define nelua_alignas(X) __attribute__((aligned(X)))
#elif defined(_MSC_VER)
  #define nelua_alignas(X) __declspec(align(X))
#else
  #define nelua_alignas(X)
#endif
]], 'directives')
end

-- Used to assure some C compiler requirements.
function cbuiltins.nelua_static_assert(context)
  context:define_builtin_macro('nelua_static_assert', [[
/* Macro used to perform compile-time checks. */
#if __STDC_VERSION__ >= 201112L
  #define nelua_static_assert _Static_assert
#elif __cplusplus >= 201103L
  #define nelua_static_assert static_assert
#else
  #define nelua_static_assert(x, y)
#endif
]], 'directives')
end

-- Used to assure some C compiler requirements.
function cbuiltins.nelua_alignof(context)
  context:define_builtin_macro('nelua_alignof', [[
/* Macro used to get alignment of a type. */
#if __STDC_VERSION__ >= 201112L
  #define nelua_alignof _Alignof
#elif __cplusplus >= 201103L
  #define nelua_alignof alignof
#elif defined(__GNUC__)
  #define nelua_alignof __alignof__
#elif defined(_MSC_VER)
  #define nelua_alignof __alignof
#else
  #define nelua_alignof(x)
#endif
]], 'directives')
end

--[[
Called before aborting when sanitizing.
Its purpose is to generate traceback before aborting.
]]
function cbuiltins.nelua_ubsan_unreachable(context)
  context:ensure_builtin('nelua_extern')
  context:define_builtin_macro('nelua_ubsan_unreachable', [[
/* Macro used to generate traceback on aborts when sanitizing. */
#if defined(__clang__) && defined(__has_feature)
  #if __has_feature(undefined_behavior_sanitizer)
    #define nelua_ubsan_unreachable __builtin_unreachable
  #endif
#elif defined(__GNUC__) && !defined(_WIN32)
  nelua_extern void __ubsan_handle_builtin_unreachable(void*) __attribute__((weak));
  #define nelua_ubsan_unreachable() {if(&__ubsan_handle_builtin_unreachable) __builtin_unreachable();}
#endif
#ifndef nelua_ubsan_unreachable
  #define nelua_ubsan_unreachable()
#endif
]], 'directives')
end

-- Used by `nil` type at runtime.
function cbuiltins.nlniltype(context)
  context:define_builtin_decl('nlniltype',
    "typedef struct nlniltype {"..
    (typedefs.emptysize == 0 and '' or 'char x;')..
    "} nlniltype;")
end

-- Used by `nil` at runtime.
function cbuiltins.NLNIL(context)
  context:ensure_builtin('nlniltype')
  context:define_builtin_macro('NLNIL', "#define NLNIL (nlniltype)"..
    (typedefs.emptysize == 0 and '{}' or '{0}'))
end

-- Used by infinite float number literal.
function cbuiltins.NLINF_(context, type)
  context:ensure_include('<math.h>')
  local S = ''
  if type.is_float128 then S = 'Q'
  elseif type.is_clongdouble then S = 'L'
  elseif type.is_float32 then S = 'F' end
  local name = 'NLINF'..S
  if context.usedbuiltins[name] then return name end
  context:define_builtin_macro(name, pegger.substitute([[
/* Infinite number constant. */
#ifdef HUGE_VAL$(S)
  #define NLINF$(S) HUGE_VAL$(S)
#else
  #define NLINF$(S) (1.0$(s)/0.0$(s))
#endif
]], {s=S:lower(), S=S}))
  return name
end

-- Used by NaN (not a number) float number literal.
function cbuiltins.NLNAN_(context, type)
  context:ensure_include('<math.h>')
  local S = ''
  if type.is_float128 then S = 'Q'
  elseif type.is_clongdouble then S = 'L'
  elseif type.is_float32 then S = 'F' end
  local name = 'NLNAN'..S
  if context.usedbuiltins[name] then return name end
  context:define_builtin_macro(name, pegger.substitute([[
/* Not a number constant. */
#ifdef NAN
  #define NLNAN$(S) (($(T))NAN)
#else
  #define NLNAN$(S) (0.0$(s)/0.0$(s))
#endif
]], {s=S:lower(), S=S, T=context:ensure_type(type)}))
  return name
end

-- Used to abort the application.
function cbuiltins.nelua_abort(context)
  local abortcall
  if context.pragmas.noabort then
    context:ensure_builtin('exit')
    abortcall = 'exit(-1)'
  else
    context:ensure_builtin('abort')
    abortcall = 'abort()'
  end
  context:ensure_builtins('fflush', 'stderr', 'nelua_ubsan_unreachable')
  context:define_function_builtin('nelua_abort',
    'nelua_noreturn', primtypes.void, {}, {[[{
  fflush(stderr);
  nelua_ubsan_unreachable();
  ]],abortcall,[[;
}]]})
end

-- Used with check functions.
function cbuiltins.nelua_panic_cstring(context)
  context:ensure_builtins('fputs', 'fputc', 'nelua_abort')
  context:define_function_builtin('nelua_panic_cstring',
    'nelua_noreturn', primtypes.void, {{'const char*', 's'}}, [[{
  fputs(s, stderr);
  fputc('\n', stderr);
  nelua_abort();
}]])
end

-- Used by `panic` builtin.
function cbuiltins.nelua_panic_string(context)
  context:ensure_builtins('fwrite', 'fputc', 'nelua_abort')
  context:define_function_builtin('nelua_panic_string',
    'nelua_noreturn', primtypes.void, {{primtypes.string, 's'}}, [[{
  if(s.size > 0) {
    fwrite(s.data, 1, s.size, stderr);
    fputc('\n', stderr);
  }
  nelua_abort();
}]])
end

-- Used by `warn` builtin.
function cbuiltins.nelua_warn(context)
  context:ensure_builtins('fputs', 'fwrite', 'fputc', 'fflush')
  context:define_function_builtin('nelua_warn',
    '', primtypes.void, {{primtypes.string, 's'}}, [[{
  if(s.size > 0) {
    fputs("warning: ", stderr);
    fwrite(s.data, 1, s.size, stderr);
    fputc('\n', stderr);
    fflush(stderr);
  }
}]])
end

--[[
Used to check conversion of a scalar to a narrow scalar.
On underflow/overflow the application will panic.
]]
function cbuiltins.nelua_assert_narrow_(context, dtype, stype)
  local name = 'nelua_assert_narrow_'..stype.codename..'_'..dtype.codename
  if context.usedbuiltins[name] then return name end
  assert(dtype.is_integral and stype.is_scalar)
  context:ensure_builtins('nelua_unlikely', 'nelua_panic_cstring')
  local emitter = CEmitter(context)
  emitter:add_ln('{') emitter:inc_indent()
  emitter:add_indent('if(nelua_unlikely(')
  if stype.is_float then -- float -> integral
    emitter:add('(',dtype,')(x) != x')
  elseif stype.is_signed and dtype.is_unsigned then -- signed -> unsigned
    emitter:add('x < 0')
    if stype.max > dtype.max then
      emitter:add(' || x > 0x', bn.tohexint(dtype.max))
    end
  elseif stype.is_unsigned and dtype.is_signed then -- unsigned -> signed
    emitter:add('x > 0x', bn.tohexint(dtype.max), 'U')
  else -- signed -> signed / unsigned -> unsigned
    emitter:add('x > 0x', bn.tohexint(dtype.max), (stype.is_unsigned and 'U' or ''))
    if stype.is_signed then -- signed -> signed
      emitter:add(' || x < ', bn.todecint(dtype.min))
    end
  end
  emitter:add_ln(')) {') emitter:inc_indent()
  emitter:add_indent_ln('nelua_panic_cstring("narrow casting from ',
      tostring(stype),' to ',tostring(dtype),' failed");')
  emitter:dec_indent() emitter:add_indent_ln('}')
  emitter:add_indent('return ')
  emitter:add_converted_val(dtype, 'x', stype, true)
  emitter:add_ln(';')
  emitter:dec_indent() emitter:add('}')
  context:define_function_builtin(name, 'nelua_inline', dtype, {{stype, 'x'}}, emitter:generate())
  return name
end

-- Used to check array bounds when indexing.
function cbuiltins.nelua_assert_bounds_(context, indextype)
  local name = 'nelua_assert_bounds_'..indextype.codename
  if context.usedbuiltins[name] then return name end
  context:ensure_builtins('nelua_panic_cstring', 'nelua_unlikely')
  context:define_function_builtin(name,
    'nelua_inline', indextype, {{indextype, 'index'}, {primtypes.usize, 'len'}}, {[[{
  if(nelua_unlikely((]],primtypes.usize,')index >= len',indextype.is_signed and ' || index < 0' or '',[[)) {
    nelua_panic_cstring("array index: position out of bounds");
  }
  return index;
}]]})
  return name
end

-- Used to check dereference of pointers.
function cbuiltins.nelua_assert_deref(context)
  context:ensure_builtins('nelua_panic_cstring', 'nelua_unlikely', 'NULL')
  context:define_function_builtin('nelua_assert_deref',
    'nelua_inline', primtypes.pointer,  {{primtypes.pointer, 'p'}}, [[{
  if(nelua_unlikely(p == NULL)) {
    nelua_panic_cstring("attempt to dereference a null pointer");
  }
  return p;
}]])
end

-- Used to convert a string to a C string.
function cbuiltins.nelua_string2cstring_(context, checked)
  local name = checked and 'nelua_assert_string2cstring' or 'nelua_string2cstring'
  if context.usedbuiltins[name] then return name end
  local code
  if checked then
    context:ensure_builtins('nelua_panic_cstring', 'nelua_unlikely')
    code = [[{
  if(s.size == 0) {
    return (char*)"";
  }
  if(nelua_unlikely(s.data[s.size]) != 0) {
    nelua_panic_cstring("attempt to convert a non null terminated string to cstring");
  }
  return (char*)s.data;
}]]
  else
    code = [[{
  return (s.size == 0) ? (char*)"" : (char*)s.data;
}]]
  end
  context:define_function_builtin(name,
    'nelua_inline', primtypes.cstring, {{primtypes.string, 's'}}, code)
  return name
end

-- Used to convert a C string to a string.
function cbuiltins.nelua_cstring2string(context)
  context:ensure_builtins('strlen', 'NULL')
  context:define_function_builtin('nelua_cstring2string',
    'nelua_inline', primtypes.string, {{'const char*', 's'}}, {[[{
  if(s == NULL) {
    return (]],primtypes.string,[[){0};
  }
  ]], primtypes.usize, [[ size = strlen(s);
  if(size == 0) {
    return (]],primtypes.string,[[){0};
  }
  return (]],primtypes.string,[[){(]],primtypes.byte,[[*)s, size};
}]]})
end

-- Used by integer less than operator (`<`).
function cbuiltins.nelua_lt_(context, ltype, rtype)
  local name = 'nelua_lt_'..ltype.codename..'_'..rtype.codename
  if context.usedbuiltins[name] then return name end
  local emitter = CEmitter(context)
  if ltype.is_signed and rtype.is_unsigned then
    emitter:add([[{
  return a < 0 || (]],ltype:unsigned_type(),[[)a < b;
}]])
  else
    assert(ltype.is_unsigned and rtype.is_signed)
    emitter:add([[{
  return b > 0 && a < (]],rtype:unsigned_type(),[[)b;
}]])
  end
  context:define_function_builtin(name,
    'nelua_inline', primtypes.boolean, {{ltype, 'a'}, {rtype, 'b'}}, emitter:generate())
  return name
end

-- Used by equality operator (`==`).
function cbuiltins.nelua_eq_(context, ltype, rtype)
  if not rtype then -- comparing same type
    local type = ltype
    local name = 'nelua_eq_'..type.codename
    if context.usedbuiltins[name] then return name end
    assert(type.is_composite)
    local defemitter = CEmitter(context)
    defemitter:add_ln('{') defemitter:inc_indent()
    defemitter:add_indent('return ')
    if type.is_union then
      defemitter:add_builtin('memcmp')
      defemitter:add('(&a, &b, sizeof(', type, ')) == 0')
    elseif #type.fields > 0 then
      for i,field in ipairs(type.fields) do
        if i > 1 then
          defemitter:add(' && ')
        end
        local fieldname, fieldtype = field.name, field.type
        if fieldtype.is_composite then
          defemitter:add_builtin('nelua_eq_', fieldtype)
          defemitter:add('(a.', fieldname, ', b.', fieldname, ')')
        elseif fieldtype.is_array then
          defemitter:add_builtin('memcmp')
          defemitter:add('(a.', fieldname, ', ', 'b.', fieldname, ', sizeof(', type, ')) == 0')
        else
          defemitter:add('a.', fieldname, ' == ', 'b.', fieldname)
        end
      end
    else
      defemitter:add(true)
    end
    defemitter:add_ln(';')
    defemitter:dec_indent() defemitter:add_ln('}')
    context:define_function_builtin(name,
      'nelua_inline', primtypes.boolean, {{type, 'a'}, {type, 'b'}},
      defemitter:generate())
    return name
  else -- comparing different types
    local name = 'nelua_eq_'..ltype.codename..'_'..rtype.codename
    if context.usedbuiltins[name] then return name end
    assert(ltype.is_integral and ltype.is_signed and rtype.is_unsigned)
    local mtype = primtypes['uint'..math.max(ltype.bitsize, rtype.bitsize)]
    context:define_function_builtin(name,
      'nelua_inline', primtypes.boolean, {{ltype, 'a'}, {rtype, 'b'}}, {[[{
  return (]],mtype,[[)a == (]],mtype,[[)b && a >= 0;
}]]})
    return name
  end
end

-- Used by string equality operator (`==`).
function cbuiltins.nelua_eq_string(context)
  context:ensure_builtins('memcmp')
  context:define_function_builtin('nelua_eq_string',
    'nelua_inline', primtypes.boolean, {{primtypes.string, 'a'}, {primtypes.string, 'b'}}, [[{
  return a.size == b.size && (a.data == b.data || a.size == 0 || memcmp(a.data, b.data, a.size) == 0);
}]])
end

-- Used by integer division operator (`//`).
function cbuiltins.nelua_idiv_(context, type, checked)
  local name = (checked and 'nelua_assert_idiv_' or 'nelua_idiv_')..type.codename
  if context.usedbuiltins[name] then return name end
  assert(type.is_signed)
  local stype, utype = type:signed_type(), type:unsigned_type()
  context:ensure_builtins('nelua_unlikely', 'nelua_panic_cstring')
  local emitter = CEmitter(context)
  emitter:add_ln('{') emitter:inc_indent()
  emitter:add_indent_ln('if(nelua_unlikely(b == -1)) return 0U - (', utype ,')a;')
  if not checked then
    emitter:add_indent_ln('if(nelua_unlikely(b == 0)) nelua_panic_cstring("division by zero");')
  end
  emitter:add_indent_ln(stype,' q = a / b;')
  emitter:add_indent_ln('return q * b == a ? q : q - ((a < 0) ^ (b < 0));')
  emitter:dec_indent() emitter:add('}')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {type, 'b'}}, emitter:generate())
  return name
end

-- Used by integer modulo operator (`%`).
function cbuiltins.nelua_imod_(context, type, checked)
  local name = (checked and  'nelua_assert_imod_' or 'nelua_imod_')..type.codename
  if context.usedbuiltins[name] then return name end
  assert(type.is_signed)
  context:ensure_builtins('nelua_unlikely', 'nelua_panic_cstring')
  local emitter = CEmitter(context)
  emitter:add_ln('{') emitter:inc_indent()
  emitter:add_indent_ln('if(nelua_unlikely(b == -1)) return 0;')
  if checked then
    emitter:add_indent_ln('if(nelua_unlikely(b == 0)) nelua_panic_cstring("division by zero");')
  end
  emitter:add_indent_ln(type,' r = a % b;')
  emitter:add_indent_ln('return (r != 0 && (a ^ b) < 0) ? r + b : r;')
  emitter:dec_indent() emitter:add('}')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {type, 'b'}}, emitter:generate())
  return name
end

-- Used by float modulo operator (`%`).
function cbuiltins.nelua_fmod_(context, type)
  local cfmod = type.is_float32 and 'fmodf' or 'fmod'
  local name = 'nelua_'..cfmod
  if context.usedbuiltins[name] then return name end
  context:ensure_builtins(cfmod, 'nelua_unlikely')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {type, 'b'}}, {[[{
  ]],type,[[ r = ]],cfmod,[[(a, b);
  if(nelua_unlikely((r > 0 && b < 0) || (r < 0 && b > 0))) {
    r += b;
  }
  return r;
}]]})
  return name
end

-- Used by integer logical shift left operator (`<<`).
function cbuiltins.nelua_shl_(context, type)
  local name = 'nelua_shl_'..type.codename
  if context.usedbuiltins[name] then return name end
  local bitsize, stype, utype = type.bitsize, type:signed_type(), type:unsigned_type()
  context:ensure_builtins('nelua_likely', 'nelua_unlikely')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {stype, 'b'}},
    {[[{
  if(nelua_likely(b >= 0 && b < ]],bitsize,[[)) {
    return ((]],utype,[[)a) << b;
  } else if(nelua_unlikely(b < 0 && b > -]],bitsize,[[)) {
    return (]],utype,[[)a >> -b;
  } else {
    return 0;
  }
}]]})
  return name
end

-- Used by integer logical shift right operator (`>>`).
function cbuiltins.nelua_shr_(context, type)
  local name = 'nelua_shr_'..type.codename
  if context.usedbuiltins[name] then return name end
  local bitsize, stype, utype = type.bitsize, type:signed_type(), type:unsigned_type()
  context:ensure_builtins('nelua_likely', 'nelua_unlikely')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {stype, 'b'}},
    {[[{
  if(nelua_likely(b >= 0 && b < ]],bitsize,[[)) {
    return (]],utype,[[)a >> b;
  } else if(nelua_unlikely(b < 0 && b > -]],bitsize,[[)) {
    return (]],utype,[[)a << -b;
  } else {
    return 0;
  }
}]]})
  return name
end

-- Used by integer arithmetic shift right operator (`>>>`).
function cbuiltins.nelua_asr_(context, type)
  local name = 'nelua_asr_'..type.codename
  if context.usedbuiltins[name] then return name end
  local bitsize = type.bitsize
  context:ensure_builtins('nelua_likely', 'nelua_unlikely')
  context:define_function_builtin(name,
    'nelua_inline', type, {{type, 'a'}, {type:signed_type(), 'b'}},
    {[[{
  if(nelua_likely(b >= 0 && b < ]],bitsize,[[)) {
    return a >> b;
  } else if(nelua_unlikely(b >= ]],bitsize,[[)) {
    return a < 0 ? -1 : 0;
  } else if(nelua_unlikely(b < 0 && b > -]],bitsize,[[)) {
    return a << -b;
  } else {
    return 0;
  }
}]]})
  return name
end

--------------------------------------------------------------------------------
--[[
Call builtins.
These builtins may overrides the callee when not returning a name.
]]
cbuiltins.calls = {}

-- Implementation of `likely` builtin.
function cbuiltins.calls.likely(context)
  return context:ensure_builtin('nelua_likely')
end

-- Implementation of `unlikely` builtin.
function cbuiltins.calls.unlikely(context)
  return context:ensure_builtin('nelua_unlikely')
end

-- Implementation of `panic` builtin.
function cbuiltins.calls.panic(context)
  return context:ensure_builtin('nelua_panic_string')
end

-- Implementation of `error` builtin.
function cbuiltins.calls.error(context)
  return context:ensure_builtin('nelua_panic_string')
end

-- Implementation of `warn` builtin.
function cbuiltins.calls.warn(context)
  return context:ensure_builtin('nelua_warn')
end

-- Implementation of `assert` builtin.
function cbuiltins.calls.assert(context, node)
  local builtintype = node.attr.builtintype
  local argattrs = builtintype.argattrs
  local funcname = context.rootscope:generate_name('nelua_assert_line')
  local emitter = CEmitter(context)
  context:ensure_builtins('fwrite', 'stderr', 'nelua_unlikely', 'nelua_abort')
  local nargs = #argattrs
  local qualifier = ''
  local assertmsg = 'assertion failed!'
  local condtype = nargs > 0 and argattrs[1].type or primtypes.void
  local rettype = builtintype.rettypes[1] or primtypes.void
  local wherenode = nargs > 0 and node[1][1] or node
  local where = wherenode:format_message('runtime error', assertmsg)
  emitter:add_ln('{')
  if nargs == 2 then
    local pos = where:find(assertmsg)
    local msg1, msg2 = where:sub(1, pos-1), where:sub(pos + #assertmsg)
    local emsg1, emsg2 = pegger.double_quote_c_string(msg1), pegger.double_quote_c_string(msg2)
    emitter:add([[
  if(nelua_unlikely(!]]) emitter:add_val2boolean('cond', condtype) emitter:add([[)) {
    fwrite(]],emsg1,[[, 1, ]],#msg1,[[, stderr);
    fwrite(msg.data, msg.size, 1, stderr);
    fwrite(]],emsg2,[[, 1, ]],#msg2,[[, stderr);
    nelua_abort();
  }
]])
  elseif nargs == 1 then
    local msg = pegger.double_quote_c_string(where)
    emitter:add([[
  if(nelua_unlikely(!]]) emitter:add_val2boolean('cond', condtype) emitter:add([[)) {
    fwrite(]],msg,[[, 1, ]],#where,[[, stderr);
    nelua_abort();
  }
]])
  else -- nargs == 0
    local msg = pegger.double_quote_c_string(where)
    qualifier = 'nelua_noreturn'
    emitter:add([[
  fwrite(]],msg,[[, 1, ]],#where,[[, stderr);
  nelua_abort();
]])
  end
  if rettype ~= primtypes.void then
    emitter:add_ln('  return cond;')
  end
  emitter:add('}')
  context:define_function_builtin(funcname, qualifier, rettype, argattrs, emitter:generate())
  return funcname
end

-- Implementation of `check` builtin.
function cbuiltins.calls.check(context, node)
  if context.pragmas.nochecks then return end -- omit call
  return cbuiltins.calls.assert(context, node)
end

-- Implementation of `require` builtin.
function cbuiltins.calls.require(context, node, emitter)
  local attr = node.attr
  if attr.alreadyrequired then
    return
  end
  local ast = attr.loadedast
  assert(not attr.runtime_require and ast)
  local bracepos = emitter:get_pos()
  emitter:add_indent_ln("{ /* require '", attr.requirename, "' */")
  local lastpos = emitter:get_pos()
  context:push_forked_state{inrequire = true}
  context:push_scope(context.rootscope)
  context:push_forked_pragmas(attr.pragmas)
  emitter:add(ast)
  context:pop_pragmas()
  context:pop_scope()
  context:pop_state()
  if emitter:get_pos() == lastpos then
    emitter:rollback(bracepos)
  else
    emitter:add_indent_ln('}')
  end
end

-- Implementation of `print` builtin.
function cbuiltins.calls.print(context, node)
  local argtypes = node.attr.builtintype.argtypes
  -- compute args hash
  local printhash = {}
  for i,argtype in ipairs(argtypes) do
    printhash[i] = argtype.codename
  end
  printhash = table.concat(printhash,' ')
  -- generate function name
  local funcname = context.printcache[printhash]
  if funcname then
    return funcname
  end
  funcname = context.rootscope:generate_name('nelua_print')
  -- function declaration
  local decemitter = CEmitter(context)
  decemitter:add('void ', funcname, '(')
  local hasfloat
  if #argtypes > 0 then
    for i,argtype in ipairs(argtypes) do
      if i>1 then decemitter:add(', ') end
      decemitter:add(argtype, ' a', i)
      if argtype.is_float then
        hasfloat = true
      end
    end
  else
    decemitter:add_text('void')
  end
  decemitter:add(')')
  local heading = decemitter:generate()
  context:add_declaration('static '..heading..';\n', funcname)
  -- function body
  local defemitter = CEmitter(context)
  defemitter:add(heading)
  defemitter:add_ln(' {')
  defemitter:inc_indent()
  if hasfloat then
    defemitter:add_indent_ln("char buff[48];")
    defemitter:add_indent_ln("buff[sizeof(buff)-1] = 0;")
    defemitter:add_indent_ln("int len;")
  end
  for i,argtype in ipairs(argtypes) do
    defemitter:add_indent()
    if i > 1 then
      context:ensure_builtins('fwrite', 'stdout')
      defemitter:add_ln("fputc('\\t', stdout);")
      defemitter:add_indent()
    end
    if argtype.is_string then
      context:ensure_builtins('fwrite', 'stdout')
      defemitter:add_ln('if(a',i,'.size > 0) {')
      defemitter:inc_indent()
      defemitter:add_indent_ln('fwrite(a',i,'.data, 1, a',i,'.size, stdout);')
      defemitter:dec_indent()
      defemitter:add_indent_ln('}')
    elseif argtype.is_cstring then
      context:ensure_builtins('fputs', 'stdout')
      defemitter:add_ln('fputs(a',i,', stdout);')
    elseif argtype.is_acstring then
      context:ensure_builtins('fputs', 'stdout')
      defemitter:add_ln('fputs((char*)a',i,', stdout);')
    elseif argtype.is_niltype then
      context:ensure_builtins('fputs', 'stdout')
      defemitter:add_ln('fputs("nil", stdout);')
    elseif argtype.is_boolean then
      context:ensure_builtins('fputs', 'stdout')
      defemitter:add_ln('fputs(a',i,' ? "true" : "false", stdout);')
    elseif argtype.is_nilptr then
      context:ensure_builtins('fputs', 'stdout')
      defemitter:add_ln('fputs("(null)", stdout);')
    elseif argtype.is_pointer or argtype.is_function then
      context:ensure_builtins('fputs', 'fprintf', 'stdout', 'PRIxPTR', 'NULL')
      if argtype.is_function then
        defemitter:add_ln('fputs("function: ", stdout);')
      end
      defemitter:add_ln('if(a',i,' != NULL) {')
        defemitter:inc_indent()
        defemitter:add_indent_ln('fprintf(stdout, "0x%" PRIxPTR, (',primtypes.isize,')a',i,');')
        defemitter:dec_indent()
      defemitter:add_indent_ln('} else {')
        defemitter:inc_indent()
        defemitter:add_indent_ln('fputs("(null)", stdout);')
        defemitter:dec_indent()
      defemitter:add_indent_ln('}')
    elseif argtype.is_float then
      context:ensure_builtins('snprintf', 'strspn', 'fwrite', 'stdout')
      local tyformat = cdefs.types_printf_format[argtype.codename]
      if not tyformat then
        node:raisef('in print: cannot handle type "%s"', argtype)
      end
      defemitter:add_ln('len = snprintf(buff, sizeof(buff)-1, ',tyformat,', a',i,');')
      defemitter:add_indent_ln('if(buff[strspn(buff, "-0123456789")] == 0) {')
        defemitter:inc_indent()
        defemitter:add_indent_ln('len = snprintf(buff, sizeof(buff)-1, "%.1f", a',i,');')
        defemitter:dec_indent()
      defemitter:add_indent_ln('}')
      defemitter:add_indent_ln('fwrite(buff, 1, len, stdout);')
    elseif argtype.is_scalar then
      context:ensure_builtins('fprintf', 'stdout')
      if argtype.is_enum then
        argtype = argtype.subtype
      end
      local tyformat = cdefs.types_printf_format[argtype.codename]
      if not tyformat then
        node:raisef('in print: cannot handle type "%s"', argtype)
      end
      local priformat = tyformat:match('PRI[%w]+')
      if priformat then
        context:ensure_builtin(priformat)
      end
      defemitter:add_ln('fprintf(stdout, ', tyformat,', a',i,');')
    elseif argtype.is_record then
      node:raisef('in print: cannot handle type "%s", you could implement `__tostring` metamethod for it', argtype)
    else --luacov:disable
      node:raisef('in print: cannot handle type "%s"', argtype)
    end --luacov:enable
  end
  context:ensure_builtins('fputc', 'fflush', 'stdout')
  defemitter:add_indent_ln([[fputc('\n', stdout);]])
  defemitter:add_indent_ln('fflush(stdout);')
  defemitter:add_ln('}')
  context:add_definition(defemitter:generate(), funcname)
  context.printcache[printhash] = funcname
  return funcname
end

--------------------------------------------------------------------------------
--[[
Binary operators.
These builtins overrides binary operations.
]]
cbuiltins.operators = {}

-- Helper to check if two nodes are comparing a signed integral with an unsigned integral.
local function needs_signed_unsigned_comparision(lattr, rattr)
  local ltype, rtype = lattr.type, rattr.type
  if not ltype.is_integral or not rtype.is_integral or
     ltype.is_unsigned == rtype.is_unsigned or
     (lattr.comptime and not ltype.is_unsigned and lattr.value >= 0) or
     (rattr.comptime and not rtype.is_unsigned and rattr.value >= 0) then
    return false
  end
  return true
end

-- Helper to implement some binary operators.
local function operator_binary_op(op, _, node, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  if ltype.is_integral and rtype.is_integral and
     ltype.is_unsigned ~= rtype.is_unsigned and
     not lattr.comptime and not rattr.comptime then
    emitter:add('(',node.attr.type,')(', lname, ' ', op, ' ', rname, ')')
  else
    assert(ltype.is_arithmetic and rtype.is_arithmetic)
    emitter:add('(', lname, ' ', op, ' ', rname, ')')
  end
end

-- Implementation of bitwise OR operator (`|`).
function cbuiltins.operators.bor(...)
  operator_binary_op('|', ...)
end

-- Implementation of bitwise XOR operator (`~`).
function cbuiltins.operators.bxor(...)
  operator_binary_op('^', ...)
end

-- Implementation of bitwise AND operator (`&`).
function cbuiltins.operators.band(...)
  operator_binary_op('&', ...)
end

-- Implementation of add operator (`*`).
function cbuiltins.operators.add(...)
  operator_binary_op('+', ...)
end

-- Implementation of subtract operator (`*`).
function cbuiltins.operators.sub(...)
  operator_binary_op('-', ...)
end

-- Implementation of multiply operator (`*`).
function cbuiltins.operators.mul(...)
  operator_binary_op('*', ...)
end

-- Implementation of division operator (`/`).
function cbuiltins.operators.div(context, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if not rtype.is_float and not ltype.is_float and type.is_float then
    emitter:add('(', lname, ' / (', type, ')', rname, ')')
  else
    operator_binary_op('/', context, node, emitter, lattr, rattr, lname, rname)
  end
end

-- Implementation of floor division operator (`//`).
function cbuiltins.operators.idiv(context, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if ltype.is_float or rtype.is_float then
    emitter:add_builtin(type.is_float32 and 'floorf' or 'floor')
    emitter:add('(', lname, ' / ', rname, ')')
  elseif type.is_integral and (lattr:is_maybe_negative() or rattr:is_maybe_negative()) then
    emitter:add_builtin('nelua_idiv_', type, not context.pragmas.nochecks)
    emitter:add('(', lname, ', ', rname, ')')
  else
    operator_binary_op('/', context, node, emitter, lattr, rattr, lname, rname)
  end
end

-- Implementation of truncate division operator (`///`).
function cbuiltins.operators.tdiv(context, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if ltype.is_float or rtype.is_float then
    emitter:add_builtin(type.is_float32 and 'truncf' or 'trunc')
    emitter:add('(', lname, ' / ', rname, ')')
  else
    operator_binary_op('/', context, node, emitter, lattr, rattr, lname, rname)
  end
end

-- Implementation of floor division remainder operator (`%`).
function cbuiltins.operators.mod(context, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if ltype.is_float or rtype.is_float then
    emitter:add_builtin('nelua_fmod_', type)
    emitter:add('(', lname, ', ', rname, ')')
  elseif type.is_integral and (lattr:is_maybe_negative() or rattr:is_maybe_negative()) then
    emitter:add_builtin('nelua_imod_', type, not context.pragmas.nochecks)
    emitter:add('(', lname, ', ', rname, ')')
  else
    operator_binary_op('%', context, node, emitter, lattr, rattr, lname, rname)
  end
end

-- Implementation of truncate division remainder operator (`%%%`).
function cbuiltins.operators.tmod(context, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if ltype.is_float or rtype.is_float then
    emitter:add_builtin(type.is_float32 and 'fmodf' or 'fmod')
    emitter:add('(', lname, ', ', rname, ')')
  else
    operator_binary_op('%', context, node, emitter, lattr, rattr, lname, rname)
  end
end

-- Implementation of logical shift left operator (`<<`).
function cbuiltins.operators.shl(_, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  assert(ltype.is_integral and rtype.is_integral)
  if rattr.comptime and rattr.value >= 0 and rattr.value < ltype.bitsize then
    -- no overflow possible, can use plain C shift
    if ltype.is_unsigned then
      emitter:add('(', lname, ' << ', rname, ')')
    else
      emitter:add('((',ltype,')((',ltype:unsigned_type(),')', lname, ' << ', rname, '))')
    end
  else
    emitter:add_builtin('nelua_shl_', type)
    emitter:add('(', lname, ', ', rname, ')')
  end
end

-- Implementation of logical shift right operator (`>>`).
function cbuiltins.operators.shr(_, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  assert(ltype.is_integral and rtype.is_integral)
  if ltype.is_unsigned and rattr.comptime and rattr.value >= 0 and rattr.value < ltype.bitsize then
    -- no overflow possible, can use plain C shift
    emitter:add('(', lname, ' >> ', rname, ')')
  else
    emitter:add_builtin('nelua_shr_', type)
    emitter:add('(', lname, ', ', rname, ')')
  end
end

-- Implementation of arithmetic shift right operator (`>>>`).
function cbuiltins.operators.asr(_, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  assert(ltype.is_integral and rtype.is_integral)
  if rattr.comptime and rattr.value >= 0 and rattr.value < ltype.bitsize then
    -- no overflow possible, can use plain C shift
    emitter:add('(', lname, ' >> ', rname, ')')
  else
    emitter:add_builtin('nelua_asr_', type)
    emitter:add('(', lname, ', ', rname, ')')
  end
end

-- Implementation of pow operator (`^`).
function cbuiltins.operators.pow(_, node, emitter, lattr, rattr, lname, rname)
  local type, ltype, rtype = node.attr.type, lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  emitter:add_builtin(type.is_float32 and 'powf' or 'pow')
  emitter:add('(', lname, ', ', rname, ')')
end

-- Implementation of less than operator (`<`).
function cbuiltins.operators.lt(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if needs_signed_unsigned_comparision(lattr, rattr) then
    emitter:add_builtin('nelua_lt_', ltype, rtype)
    emitter:add('(', lname, ', ', rname, ')')
  else
    emitter:add('(', lname, ' < ', rname, ')')
  end
end

-- Implementation of greater than operator (`>`).
function cbuiltins.operators.gt(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if needs_signed_unsigned_comparision(lattr, rattr) then
    emitter:add_builtin('nelua_lt_', rtype, ltype)
    emitter:add('(', rname, ', ', lname, ')')
  else
    emitter:add('(', lname, ' > ', rname, ')')
  end
end

-- Implementation of less or equal than operator (`<=`).
function cbuiltins.operators.le(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if needs_signed_unsigned_comparision(lattr, rattr) then
    emitter:add('!')
    emitter:add_builtin('nelua_lt_', rtype, ltype)
    emitter:add('(', rname, ', ', lname, ')')
  else
    emitter:add('(', lname, ' <= ', rname, ')')
  end
end

-- Implementation of greater or equal than operator (`>=`).
function cbuiltins.operators.ge(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  assert(ltype.is_arithmetic and rtype.is_arithmetic)
  if needs_signed_unsigned_comparision(lattr, rattr) then
    emitter:add('!')
    emitter:add_builtin('nelua_lt_', ltype, rtype)
    emitter:add('(', lname, ', ', rname, ')')
  else
    emitter:add('(', lname, ' >= ', rname, ')')
  end
end

-- Implementation of equal operator (`==`).
function cbuiltins.operators.eq(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  if ltype.is_stringy and rtype.is_stringy then
    emitter:add_builtin('nelua_eq_string')
    emitter:add('(')
    emitter:add_converted_val(primtypes.string, lname, ltype)
    emitter:add(', ')
    emitter:add_converted_val(primtypes.string, rname, rtype)
    emitter:add(')')
  elseif ltype.is_composite or rtype.is_composite then
    if ltype == rtype then
      emitter:add_builtin('nelua_eq_', ltype)
      emitter:add('(', lname, ', ', rname, ')')
    else
      emitter:add('(', lname, ', ', rname, ', ', false, ')')
    end
  elseif ltype.is_array then
    assert(ltype == rtype)
    if lattr.lvalue and rattr.lvalue and not lattr.comptime and not rattr.comptime then
      emitter:add('(')
      emitter:add_builtin('memcmp')
      emitter:add('(&', lname, ', &', rname, ', sizeof(', ltype, ')) == 0)')
    else
      emitter:add('({', ltype, ' a = ', lname, '; ',
                        rtype, ' b = ', rname, '; ')
      emitter:add_builtin('memcmp')
      emitter:add('(&a, &b, sizeof(', ltype, ')) == 0; })')
    end
  elseif needs_signed_unsigned_comparision(lattr, rattr) then
    if ltype.is_unsigned then
      ltype, rtype, lname, rname = rtype, ltype, rname, lname -- swap
    end
    emitter:add_builtin('nelua_eq_', ltype, rtype)
    emitter:add('(', lname, ', ', rname, ')')
  elseif ltype.is_scalar and rtype.is_scalar then
    emitter:add('(', lname, ' == ', rname, ')')
  elseif ltype.is_niltype or rtype.is_niltype or
         ((ltype.is_boolean or rtype.is_boolean) and ltype ~= rtype) then
    emitter:add('(', lname, ', ', rname, ', ', ltype == rtype, ')')
  else
    emitter:add('(', lname, ' == ')
    if ltype ~= rtype then
      emitter:add_converted_val(ltype, rname, rtype)
    else
      emitter:add(rname)
    end
    emitter:add(')')
  end
end

-- Implementation of not equal operator (`~=`).
function cbuiltins.operators.ne(_, _, emitter, lattr, rattr, lname, rname)
  local ltype, rtype = lattr.type, rattr.type
  if ltype.is_stringy and rtype.is_string then
    emitter:add('(!')
    emitter:add_builtin('nelua_eq_string')
    emitter:add('(')
    emitter:add_converted_val(primtypes.string, lname, ltype)
    emitter:add(', ')
    emitter:add_converted_val(primtypes.string, rname, rtype)
    emitter:add('))')
  elseif ltype.is_composite or rtype.is_composite then
    if ltype == rtype then
      emitter:add('(!')
      emitter:add_builtin('nelua_eq_', ltype)
      emitter:add('(', lname, ', ', rname, '))')
    else
      emitter:add('(', lname, ', ', rname, ', ', true, ')')
    end
  elseif ltype.is_array then
    assert(ltype == rtype)
    if lattr.lvalue and rattr.lvalue and not lattr.comptime and not rattr.comptime then
      emitter:add('(')
      emitter:add_builtin('memcmp')
      emitter:add('(&', lname, ', &', rname, ', sizeof(', ltype, ')) != 0)')
    else
      emitter:add('({', ltype, ' a = ', lname, '; ',
                        rtype, ' b = ', rname, '; ')
      emitter:add_builtin('memcmp')
      emitter:add('(&a, &b, sizeof(', ltype, ')) != 0; })')
    end
  elseif needs_signed_unsigned_comparision(lattr, rattr) then
    if ltype.is_unsigned then
      ltype, rtype, lname, rname = rtype, ltype, rname, lname -- swap
    end
    emitter:add('(!')
    emitter:add_builtin('nelua_eq_', ltype, rtype)
    emitter:add('(', lname, ', ', rname, '))')
  elseif ltype.is_scalar and rtype.is_scalar then
    emitter:add('(', lname, ' != ', rname, ')')
  elseif ltype.is_niltype or rtype.is_niltype or
         ((ltype.is_boolean or rtype.is_boolean) and ltype ~= rtype) then
    emitter:add('(', lname, ', ', rname, ', ', ltype ~= rtype, ')')
  else
    emitter:add('(', lname, ' != ')
    if ltype ~= rtype then
      emitter:add_converted_val(ltype, rname, rtype)
    else
      emitter:add(rname)
    end
    emitter:add(')')
  end
end

-- Implementation of conditional OR operator (`or`).
cbuiltins.operators["or"] = function(_, _, emitter, lattr, rattr, lname, rname)
  emitter:add_text('(')
  emitter:add_val2boolean(lname, lattr.type)
  emitter:add_text(' || ')
  emitter:add_val2boolean(rname, rattr.type)
  emitter:add_text(')')
end

-- Implementation of conditional AND operator (`and`).
cbuiltins.operators["and"] = function(_, _, emitter, lattr, rattr, lname, rname)
  emitter:add_text('(')
  emitter:add_val2boolean(lname, lattr.type)
  emitter:add_text(' && ')
  emitter:add_val2boolean(rname, rattr.type)
  emitter:add_text(')')
end

-- Implementation of not operator (`not`).
cbuiltins.operators["not"] = function(_, _, emitter, argattr, argname)
  emitter:add_text('(!')
  emitter:add_val2boolean(argname, argattr.type)
  emitter:add_text(')')
end

-- Implementation of unary minus operator (`-`).
function cbuiltins.operators.unm(_, _, emitter, argattr, argname)
  assert(argattr.type.is_arithmetic)
  emitter:add('(-', argname, ')')
end

-- Implementation of bitwise not operator (`~`).
function cbuiltins.operators.bnot(_, _, emitter, argattr, argname)
  assert(argattr.type.is_integral)
  emitter:add('(~', argname, ')')
end

-- Implementation of reference operator (`&`).
function cbuiltins.operators.ref(_, _, emitter, argattr, argname)
  assert(argattr.lvalue)
  emitter:add('(&', argname, ')')
end

-- Implementation of dereference operator (`$`).
function cbuiltins.operators.deref(_, _, emitter, argattr, argname)
  local type = argattr.type
  assert(type.is_pointer)
  emitter:add_deref(argname, type)
end

-- Implementation of length operator (`#`).
function cbuiltins.operators.len(_, node, emitter, argattr, argname)
  local type = argattr.type
  if type.is_string then
    emitter:add('((',primtypes.isize,')(', argname, ').size)')
  elseif type.is_cstring then
    emitter:add('((',primtypes.isize,')')
    emitter:add_builtin('strlen')
    emitter:add('(', argname, '))')
  elseif type.is_type then
    emitter:add('sizeof(', argattr.value, ')')
  else --luacov:disable
    node:raisef('not implemented')
  end --luacov:enable
end

return cbuiltins
