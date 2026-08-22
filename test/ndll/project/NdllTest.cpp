// A CFFI library for test/ndll: primitives that use the parts of hxcpp's CFFI a neko
//  program reaches through an ndll. Built with neko's glue, as lime is, so the one
//  binary loads on neko and on Nekomata
#define IMPLEMENT_API
#define NEKO_COMPATIBLE
#include <hx/CFFI.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>

// Neko numbers its value types as hxcpp does, except abstracts, which neko's glue gives
//  one type and hxcpp one per kind
value nt_type(value v)
{
   return alloc_int(val_is_abstract(v) ? valtAbstractBase : val_type(v));
}
DEFINE_PRIM(nt_type, 1);

value nt_add(value a, value b)
{
   if (val_is_int(a) && val_is_int(b))
      return alloc_int(val_int(a) + val_int(b));
   return alloc_float(val_number(a) + val_number(b));
}
DEFINE_PRIM(nt_add, 2);

value nt_bool(value v)
{
   return alloc_bool(!val_bool(v));
}
DEFINE_PRIM(nt_bool, 1);

value nt_concat(value a, value b)
{
   std::string s = std::string(val_string(a)) + "+" + val_string(b);
   return alloc_string(s.c_str());
}
DEFINE_PRIM(nt_concat, 2);

value nt_strlen(value s)
{
   return alloc_int(val_strlen(s));
}
DEFINE_PRIM(nt_strlen, 1);

value nt_string_len(value s, value n)
{
   return alloc_string_len(val_string(s), val_int(n));
}
DEFINE_PRIM(nt_string_len, 2);

// -- Objects --

value nt_object()
{
   value o = alloc_empty_object();
   alloc_field(o, val_id("count"), alloc_int(3));
   alloc_field(o, val_id("ratio"), alloc_float(0.25));
   alloc_field(o, val_id("name"), alloc_string("made in C"));
   alloc_field(o, val_id("ok"), alloc_bool(true));
   value inner = alloc_empty_object();
   alloc_field(inner, val_id("depth"), alloc_int(2));
   alloc_field(o, val_id("inner"), inner);
   value list = alloc_array(3);
   val_array_set_i(list, 0, alloc_int(1));
   val_array_set_i(list, 1, alloc_string("two"));
   val_array_set_i(list, 2, alloc_float(3.5));
   alloc_field(o, val_id("list"), list);
   return o;
}
DEFINE_PRIM(nt_object, 0);

value nt_get_field(value o, value name)
{
   return val_field(o, val_id(val_string(name)));
}
DEFINE_PRIM(nt_get_field, 2);

value nt_set_field(value o, value name, value v)
{
   alloc_field(o, val_id(val_string(name)), v);
   return alloc_null();
}
DEFINE_PRIM(nt_set_field, 3);

value nt_field_number(value o, value name)
{
   return alloc_float(val_field_numeric(o, val_id(val_string(name))));
}
DEFINE_PRIM(nt_field_number, 2);

static void collect_field(value v, field id, void *cookie)
{
   std::string *names = (std::string *)cookie;
   if (!names->empty())
      *names += ",";
   *names += val_string(val_field_name(id));
   *names += "=";
   *names += val_is_int(v) ? "int" : val_is_string(v) ? "string" : val_is_object(v) ? "object" : "other";
}

value nt_fields(value o)
{
   std::string names;
   val_iter_field_vals(o, collect_field, &names);
   return alloc_string(names.c_str());
}
DEFINE_PRIM(nt_fields, 1);

// -- Arrays --

value nt_array_sum(value a)
{
   double sum = 0;
   int n = val_array_size(a);
   for(int i = 0; i < n; i++)
      sum += val_number(val_array_i(a, i));
   return alloc_float(sum);
}
DEFINE_PRIM(nt_array_sum, 1);

value nt_array_double(value a)
{
   int n = val_array_size(a);
   for(int i = 0; i < n; i++)
      val_array_set_i(a, i, alloc_int(val_int(val_array_i(a, i)) * 2));
   return alloc_null();
}
DEFINE_PRIM(nt_array_double, 1);

value nt_array_make(value n)
{
   value a = alloc_array(val_int(n));
   for(int i = 0; i < val_int(n); i++)
      val_array_set_i(a, i, alloc_int(i * i));
   return a;
}
DEFINE_PRIM(nt_array_make, 1);

// -- Functions --

value nt_call(value f, value a)
{
   return val_call1(f, a);
}
DEFINE_PRIM(nt_call, 2);

value nt_call2(value f, value a, value b)
{
   return val_call2(f, a, b);
}
DEFINE_PRIM(nt_call2, 3);

value nt_ocall(value o, value name, value a)
{
   return val_ocall1(o, val_id(val_string(name)), a);
}
DEFINE_PRIM(nt_ocall, 3);

value nt_nargs(value f)
{
   return alloc_int(val_fun_nargs(f));
}
DEFINE_PRIM(nt_nargs, 1);

// A callback kept past the call that gave it, as event handlers are
static AutoGCRoot *kept = 0;

value nt_keep(value f)
{
   if (kept)
      kept->set(f);
   else
      kept = new AutoGCRoot(f);
   return alloc_null();
}
DEFINE_PRIM(nt_keep, 1);

value nt_fire(value a)
{
   return kept ? val_call1(kept->get(), a) : alloc_null();
}
DEFINE_PRIM(nt_fire, 1);

value nt_sum(value *args, int n)
{
   int sum = 0;
   for(int i = 0; i < n; i++)
      sum += val_int(args[i]);
   return alloc_int(sum * 100 + n);
}
DEFINE_PRIM_MULT(nt_sum);

// -- Exceptions --

value nt_throw(value v)
{
   val_throw(v);
   return alloc_null();
}
DEFINE_PRIM(nt_throw, 1);

value nt_throw_string(value s)
{
   val_throw(alloc_string(val_string(s)));
   return alloc_null();
}
DEFINE_PRIM(nt_throw_string, 1);

// -- Abstracts --

DEFINE_KIND(k_counter);

value nt_counter(value start)
{
   if (!k_counter)
      k_counter = alloc_kind();
   int *n = new int(val_int(start));
   return alloc_abstract(k_counter, n);
}
DEFINE_PRIM(nt_counter, 1);

value nt_counter_next(value c)
{
   int *n = (int *)val_to_kind(c, k_counter);
   if (!n)
      return alloc_string("not a counter");
   return alloc_int((*n)++);
}
DEFINE_PRIM(nt_counter_next, 1);

// -- Bytes and buffers --

value nt_bytes_sum(value bytes)
{
   CffiBytes b = getByteData(bytes);
   if (!b.data)
      return alloc_null();
   int sum = 0;
   for(int i = 0; i < b.length; i++)
      sum += b.data[i];
   return alloc_int(sum);
}
DEFINE_PRIM(nt_bytes_sum, 1);

value nt_bytes_fill(value bytes, value c)
{
   CffiBytes b = getByteData(bytes);
   if (b.data)
      memset(b.data, val_int(c), b.length);
   return alloc_null();
}
DEFINE_PRIM(nt_bytes_fill, 2);

value nt_buffer(value a, value b, value c)
{
   buffer buf = alloc_buffer("values:");
   val_buffer(buf, a);
   buffer_append(buf, "|");
   val_buffer(buf, b);
   buffer_append(buf, "|");
   val_buffer(buf, c);
   return buffer_to_string(buf);
}
DEFINE_PRIM(nt_buffer, 3);
