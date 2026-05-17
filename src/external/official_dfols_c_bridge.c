/*
 * Official DFO-LS in-process bridge for TLTM.
 *
 * TLTM owns the residual callback and the residual acceptance gate. This file
 * only calls the official Python DFO-LS package through Python's C API.
 */

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef int (*tltm_dfols_objfun_cb)(void *ctx, int n, const double *x, double *r);

#ifndef TLTM_ENABLE_OFFICIAL_DFOLS

int tltm_official_dfols_solve(
    int n,
    const double *x0,
    double *x_out,
    double *package_residual_norm,
    int *nf,
    int *flag,
    int npt,
    double rhobeg,
    double rhoend,
    int maxfun,
    int objfun_has_noise,
    double model_abs_tol,
    double model_rel_tol,
    void *ctx,
    tltm_dfols_objfun_cb objfun)
{
    int i;
    (void)npt;
    (void)rhobeg;
    (void)rhoend;
    (void)maxfun;
    (void)objfun_has_noise;
    (void)model_abs_tol;
    (void)model_rel_tol;
    (void)ctx;
    (void)objfun;
    if (package_residual_norm) *package_residual_norm = HUGE_VAL;
    if (nf) *nf = 0;
    if (flag) *flag = -1000;
    if (n > 0 && x0 && x_out) {
        for (i = 0; i < n; ++i) x_out[i] = x0[i];
    }
    return 1000;
}

#else

#include <Python.h>

typedef struct {
    PyObject_HEAD
    int n;
    void *ctx;
    tltm_dfols_objfun_cb objfun;
} TltmObjfunObject;

static PyObject *TltmObjfun_call(PyObject *self_obj, PyObject *args, PyObject *kwargs)
{
    (void)kwargs;
    TltmObjfunObject *self = (TltmObjfunObject *)self_obj;
    PyObject *x_obj = NULL;
    PyObject *x_seq = NULL;
    PyObject *result = NULL;
    double *x = NULL;
    double *r = NULL;
    Py_ssize_t n_seq = 0;
    int i = 0;
    int status = 0;

    if (!PyArg_ParseTuple(args, "O", &x_obj)) return NULL;
    x_seq = PySequence_Fast(x_obj, "DFO-LS objective input is not a sequence");
    if (!x_seq) return NULL;

    n_seq = PySequence_Fast_GET_SIZE(x_seq);
    if (n_seq != (Py_ssize_t)self->n) {
        PyErr_SetString(PyExc_ValueError, "DFO-LS objective input length mismatch");
        Py_DECREF(x_seq);
        return NULL;
    }

    x = (double *)calloc((size_t)self->n, sizeof(double));
    r = (double *)calloc((size_t)self->n, sizeof(double));
    if (!x || !r) {
        PyErr_NoMemory();
        free(x);
        free(r);
        Py_DECREF(x_seq);
        return NULL;
    }

    for (i = 0; i < self->n; ++i) {
        PyObject *item = PySequence_Fast_GET_ITEM(x_seq, i);
        x[i] = PyFloat_AsDouble(item);
        if (PyErr_Occurred()) {
            free(x);
            free(r);
            Py_DECREF(x_seq);
            return NULL;
        }
    }

    status = self->objfun(self->ctx, self->n, x, r);
    if (status != 0) {
        PyErr_SetString(PyExc_RuntimeError, "TLTM residual callback failed");
        free(x);
        free(r);
        Py_DECREF(x_seq);
        return NULL;
    }

    result = PyList_New(self->n);
    if (!result) {
        free(x);
        free(r);
        Py_DECREF(x_seq);
        return NULL;
    }
    for (i = 0; i < self->n; ++i) {
        PyObject *value = PyFloat_FromDouble(r[i]);
        if (!value) {
            Py_DECREF(result);
            free(x);
            free(r);
            Py_DECREF(x_seq);
            return NULL;
        }
        PyList_SET_ITEM(result, i, value);
    }

    free(x);
    free(r);
    Py_DECREF(x_seq);
    return result;
}

static PyTypeObject TltmObjfunType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "tltm_official_dfols.Objfun",
    .tp_basicsize = sizeof(TltmObjfunObject),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_call = TltmObjfun_call,
};

static int bridge_ready = 0;
static PyObject *dfols_module = NULL;
static PyObject *dfols_solve = NULL;

static int append_sys_path_entries(const char *path_text)
{
    PyObject *sys_path = NULL;
    char *buffer = NULL;
    char *token = NULL;
    char *saveptr = NULL;

    if (!path_text || !path_text[0]) return 0;
    sys_path = PySys_GetObject("path");
    if (!sys_path) return 1;

    buffer = strdup(path_text);
    if (!buffer) return 1;

    token = strtok_r(buffer, ":", &saveptr);
    while (token) {
        if (token[0]) {
            PyObject *entry = PyUnicode_FromString(token);
            if (!entry) {
                free(buffer);
                return 1;
            }
            if (PyList_Insert(sys_path, 0, entry) != 0) {
                Py_DECREF(entry);
                free(buffer);
                return 1;
            }
            Py_DECREF(entry);
        }
        token = strtok_r(NULL, ":", &saveptr);
    }

    free(buffer);
    return 0;
}

static int ensure_bridge_ready(void)
{
    const char *extra_path = NULL;

    if (bridge_ready) return 0;

    if (!Py_IsInitialized()) {
        Py_Initialize();
    }
    if (PyType_Ready(&TltmObjfunType) < 0) return 10;

    extra_path = getenv("TLTM_OFFICIAL_DFOLS_PYTHONPATH");
    if (append_sys_path_entries(extra_path) != 0) return 11;

    dfols_module = PyImport_ImportModule("dfols");
    if (!dfols_module) {
        PyErr_Print();
        return 12;
    }
    dfols_solve = PyObject_GetAttrString(dfols_module, "solve");
    if (!dfols_solve || !PyCallable_Check(dfols_solve)) {
        PyErr_Print();
        return 13;
    }

    bridge_ready = 1;
    return 0;
}

static PyObject *double_list_from_array(int n, const double *values)
{
    PyObject *list = PyList_New(n);
    int i = 0;

    if (!list) return NULL;
    for (i = 0; i < n; ++i) {
        PyObject *value = PyFloat_FromDouble(values[i]);
        if (!value) {
            Py_DECREF(list);
            return NULL;
        }
        PyList_SET_ITEM(list, i, value);
    }
    return list;
}

static double sequence_norm2(PyObject *seq_obj, int n)
{
    PyObject *seq = PySequence_Fast(seq_obj, "residual is not a sequence");
    double norm_sq = 0.0;
    int i = 0;

    if (!seq) return HUGE_VAL;
    if (PySequence_Fast_GET_SIZE(seq) != (Py_ssize_t)n) {
        Py_DECREF(seq);
        return HUGE_VAL;
    }
    for (i = 0; i < n; ++i) {
        PyObject *item = PySequence_Fast_GET_ITEM(seq, i);
        double value = PyFloat_AsDouble(item);
        if (PyErr_Occurred()) {
            Py_DECREF(seq);
            return HUGE_VAL;
        }
        norm_sq += value * value;
    }
    Py_DECREF(seq);
    return sqrt(norm_sq);
}

static int copy_sequence_to_array(PyObject *seq_obj, int n, double *values)
{
    PyObject *seq = PySequence_Fast(seq_obj, "solution is not a sequence");
    int i = 0;

    if (!seq) return 1;
    if (PySequence_Fast_GET_SIZE(seq) != (Py_ssize_t)n) {
        Py_DECREF(seq);
        return 2;
    }
    for (i = 0; i < n; ++i) {
        PyObject *item = PySequence_Fast_GET_ITEM(seq, i);
        values[i] = PyFloat_AsDouble(item);
        if (PyErr_Occurred()) {
            Py_DECREF(seq);
            return 3;
        }
    }
    Py_DECREF(seq);
    return 0;
}

static int dict_set_long(PyObject *dict, const char *key, long value)
{
    PyObject *obj = PyLong_FromLong(value);
    int status = 0;

    if (!obj) return 1;
    status = PyDict_SetItemString(dict, key, obj);
    Py_DECREF(obj);
    return status;
}

static int dict_set_double(PyObject *dict, const char *key, double value)
{
    PyObject *obj = PyFloat_FromDouble(value);
    int status = 0;

    if (!obj) return 1;
    status = PyDict_SetItemString(dict, key, obj);
    Py_DECREF(obj);
    return status;
}

static int dict_set_bool(PyObject *dict, const char *key, int value)
{
    return PyDict_SetItemString(dict, key, value ? Py_True : Py_False);
}

int tltm_official_dfols_solve(
    int n,
    const double *x0,
    double *x_out,
    double *package_residual_norm,
    int *nf,
    int *flag,
    int npt,
    double rhobeg,
    double rhoend,
    int maxfun,
    int objfun_has_noise,
    double model_abs_tol,
    double model_rel_tol,
    void *ctx,
    tltm_dfols_objfun_cb objfun)
{
    PyGILState_STATE gil_state;
    PyObject *args = NULL;
    PyObject *kwargs = NULL;
    PyObject *x0_obj = NULL;
    PyObject *objfun_obj = NULL;
    PyObject *user_params = NULL;
    PyObject *soln = NULL;
    PyObject *soln_x = NULL;
    PyObject *soln_resid = NULL;
    PyObject *attr = NULL;
    int status = 0;
    int i = 0;

    if (package_residual_norm) *package_residual_norm = HUGE_VAL;
    if (nf) *nf = 0;
    if (flag) *flag = -999;
    if (n <= 0 || !x0 || !x_out || !objfun) return 1;
    for (i = 0; i < n; ++i) x_out[i] = x0[i];

    if (!Py_IsInitialized()) {
        Py_Initialize();
    }
    gil_state = PyGILState_Ensure();
    status = ensure_bridge_ready();
    if (status != 0) {
        PyGILState_Release(gil_state);
        return status;
    }

    objfun_obj = TltmObjfunType.tp_alloc(&TltmObjfunType, 0);
    if (!objfun_obj) {
        PyGILState_Release(gil_state);
        return 20;
    }
    ((TltmObjfunObject *)objfun_obj)->n = n;
    ((TltmObjfunObject *)objfun_obj)->ctx = ctx;
    ((TltmObjfunObject *)objfun_obj)->objfun = objfun;

    x0_obj = double_list_from_array(n, x0);
    if (!x0_obj) {
        Py_DECREF(objfun_obj);
        PyGILState_Release(gil_state);
        return 21;
    }

    args = PyTuple_Pack(2, objfun_obj, x0_obj);
    kwargs = PyDict_New();
    user_params = PyDict_New();
    if (!args || !kwargs || !user_params) {
        status = 22;
        goto cleanup;
    }

    if (dict_set_long(kwargs, "maxfun", maxfun) != 0) { status = 23; goto cleanup; }
    if (dict_set_double(kwargs, "rhoend", rhoend) != 0) { status = 24; goto cleanup; }
    if (dict_set_bool(kwargs, "objfun_has_noise", objfun_has_noise) != 0) { status = 25; goto cleanup; }
    if (dict_set_bool(kwargs, "do_logging", 0) != 0) { status = 26; goto cleanup; }
    if (dict_set_bool(kwargs, "print_progress", 0) != 0) { status = 27; goto cleanup; }
    if (npt > 0) {
        if (dict_set_long(kwargs, "npt", npt) != 0) { status = 28; goto cleanup; }
    }
    if (rhobeg > 0.0) {
        if (dict_set_double(kwargs, "rhobeg", rhobeg) != 0) { status = 29; goto cleanup; }
    }
    if (model_abs_tol > 0.0) {
        if (dict_set_double(user_params, "model.abs_tol", model_abs_tol) != 0) { status = 30; goto cleanup; }
    }
    if (model_rel_tol >= 0.0) {
        if (dict_set_double(user_params, "model.rel_tol", model_rel_tol) != 0) { status = 31; goto cleanup; }
    }
    if (PyDict_Size(user_params) > 0) {
        if (PyDict_SetItemString(kwargs, "user_params", user_params) != 0) { status = 32; goto cleanup; }
    }

    soln = PyObject_Call(dfols_solve, args, kwargs);
    if (!soln) {
        PyErr_Print();
        status = 40;
        goto cleanup;
    }

    soln_x = PyObject_GetAttrString(soln, "x");
    soln_resid = PyObject_GetAttrString(soln, "resid");
    if (!soln_x || !soln_resid) {
        PyErr_Print();
        status = 41;
        goto cleanup;
    }
    if (copy_sequence_to_array(soln_x, n, x_out) != 0) {
        PyErr_Print();
        status = 42;
        goto cleanup;
    }
    if (package_residual_norm) *package_residual_norm = sequence_norm2(soln_resid, n);

    if (nf) {
        attr = PyObject_GetAttrString(soln, "nf");
        if (attr) {
            *nf = (int)PyLong_AsLong(attr);
            Py_DECREF(attr);
            attr = NULL;
        } else {
            PyErr_Clear();
        }
    }
    if (flag) {
        attr = PyObject_GetAttrString(soln, "flag");
        if (attr) {
            *flag = (int)PyLong_AsLong(attr);
            Py_DECREF(attr);
            attr = NULL;
        } else {
            PyErr_Clear();
        }
    }

cleanup:
    Py_XDECREF(soln_resid);
    Py_XDECREF(soln_x);
    Py_XDECREF(soln);
    Py_XDECREF(user_params);
    Py_XDECREF(kwargs);
    Py_XDECREF(args);
    Py_XDECREF(x0_obj);
    Py_XDECREF(objfun_obj);
    PyGILState_Release(gil_state);
    return status;
}

#endif
