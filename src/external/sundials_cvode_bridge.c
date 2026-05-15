#include <stddef.h>

typedef int (*tltm_cvode_rhs_cb)(void *user_ctx, int n, double t, const double *y, double *ydot);

enum {
    TLTM_CVODE_STATUS_SUCCESS = 0,
    TLTM_CVODE_STATUS_MAX_STEPS = 1,
    TLTM_CVODE_STATUS_INVALID = 2,
    TLTM_CVODE_STATUS_UNAVAILABLE = 10
};

#ifdef TLTM_ENABLE_SUNDIALS_CVODE

#include <math.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include <cvode/cvode.h>
#include <nvector/nvector_serial.h>
#include <sunnonlinsol/sunnonlinsol_fixedpoint.h>
#include <sundials/sundials_nonlinearsolver.h>
#include <sundials/sundials_context.h>
#include <sundials/sundials_types.h>

typedef struct {
    int n;
    void *user_ctx;
    tltm_cvode_rhs_cb rhs_cb;
    long int rhs_evals;
} tltm_cvode_bridge_ctx;

static int tltm_cvode_values_are_finite(const double *values, int n)
{
    int i;
    if (values == NULL || n <= 0) return 0;
    for (i = 0; i < n; ++i) {
        if (!isfinite(values[i])) return 0;
    }
    return 1;
}

static int tltm_cvode_rhs(double t, N_Vector y, N_Vector ydot, void *user_data)
{
    tltm_cvode_bridge_ctx *bridge = (tltm_cvode_bridge_ctx *)user_data;
    double *y_data = NULL;
    double *ydot_data = NULL;
    int rc;

    if (bridge == NULL || bridge->rhs_cb == NULL || bridge->n <= 0) return -1;

    y_data = N_VGetArrayPointer_Serial(y);
    ydot_data = N_VGetArrayPointer_Serial(ydot);
    if (y_data == NULL || ydot_data == NULL) return -1;

    rc = bridge->rhs_cb(bridge->user_ctx, bridge->n, t, y_data, ydot_data);
    if (rc != 0) return -1;
    if (!tltm_cvode_values_are_finite(ydot_data, bridge->n)) return -1;
    bridge->rhs_evals += 1;

    return 0;
}

static int tltm_cvode_long_to_int_nonnegative(long int value)
{
    if (value <= 0) return 0;
    if (value > (long int)INT_MAX) return INT_MAX;
    return (int)value;
}

int tltm_sundials_cvode_available(void)
{
    return 1;
}

int tltm_sundials_cvode_integrate(int n,
                                  const double *y0,
                                  double t_final,
                                  double abs_tol,
                                  double rel_tol,
                                  int max_num_steps,
                                  int fixedpoint_m,
                                  int max_order,
                                  double *y_out,
                                  int *num_steps_out,
                                  double *last_step_out,
                                  double *t_reached_out,
                                  int *rhs_evals_out,
                                  int *error_test_fails_out,
                                  int *nonlinear_iters_out,
                                  int *nonlinear_conv_fails_out,
                                  int *step_solve_fails_out,
                                  int *last_order_out,
                                  void *user_ctx,
                                  tltm_cvode_rhs_cb rhs_cb)
{
    SUNContext sunctx = NULL;
    N_Vector y = NULL;
    SUNNonlinearSolver nls = NULL;
    void *cvode_mem = NULL;
    double *y_storage = NULL;
    sunrealtype t_reached_sun = 0.0;
    sunrealtype last_step_sun = 0.0;
    double t_reached = 0.0;
    long int num_steps = 0;
    long int num_rhs_evals = 0;
    long int num_error_test_fails = 0;
    long int num_nonlinear_iters = 0;
    long int num_nonlinear_conv_fails = 0;
    long int num_step_solve_fails = 0;
    double last_step = 0.0;
    int last_order = 0;
    int retval = CV_SUCCESS;
    int status = TLTM_CVODE_STATUS_INVALID;
    tltm_cvode_bridge_ctx bridge;

    if (num_steps_out != NULL) *num_steps_out = 0;
    if (last_step_out != NULL) *last_step_out = 0.0;
    if (t_reached_out != NULL) *t_reached_out = 0.0;
    if (rhs_evals_out != NULL) *rhs_evals_out = 0;
    if (error_test_fails_out != NULL) *error_test_fails_out = 0;
    if (nonlinear_iters_out != NULL) *nonlinear_iters_out = 0;
    if (nonlinear_conv_fails_out != NULL) *nonlinear_conv_fails_out = 0;
    if (step_solve_fails_out != NULL) *step_solve_fails_out = 0;
    if (last_order_out != NULL) *last_order_out = 0;

    if (n <= 0 || y0 == NULL || y_out == NULL || rhs_cb == NULL) return TLTM_CVODE_STATUS_INVALID;
    if (abs_tol < 0.0 || rel_tol < 0.0 || (abs_tol == 0.0 && rel_tol == 0.0)) return TLTM_CVODE_STATUS_INVALID;
    if (!tltm_cvode_values_are_finite(y0, n)) return TLTM_CVODE_STATUS_INVALID;

    y_storage = (double *)malloc((size_t)n * sizeof(double));
    if (y_storage == NULL) return TLTM_CVODE_STATUS_INVALID;
    memcpy(y_storage, y0, (size_t)n * sizeof(double));

    if (SUNContext_Create(SUN_COMM_NULL, &sunctx) != 0) goto cleanup;

    y = N_VMake_Serial((sunindextype)n, y_storage, sunctx);
    if (y == NULL) goto cleanup;

    cvode_mem = CVodeCreate(CV_ADAMS, sunctx);
    if (cvode_mem == NULL) goto cleanup;

    bridge.n = n;
    bridge.user_ctx = user_ctx;
    bridge.rhs_cb = rhs_cb;
    bridge.rhs_evals = 0;

    retval = CVodeInit(cvode_mem, tltm_cvode_rhs, 0.0, y);
    if (retval != CV_SUCCESS) goto cvode_failure;

    nls = SUNNonlinSol_FixedPoint(y, fixedpoint_m > 0 ? fixedpoint_m : 0, sunctx);
    if (nls == NULL) goto cleanup;

    retval = CVodeSetNonlinearSolver(cvode_mem, nls);
    if (retval != CV_SUCCESS) goto cvode_failure;

    retval = CVodeSStolerances(cvode_mem, (sunrealtype)rel_tol, (sunrealtype)abs_tol);
    if (retval != CV_SUCCESS) goto cvode_failure;

    retval = CVodeSetUserData(cvode_mem, &bridge);
    if (retval != CV_SUCCESS) goto cvode_failure;

    if (max_num_steps > 0) {
        retval = CVodeSetMaxNumSteps(cvode_mem, (long int)max_num_steps);
        if (retval != CV_SUCCESS) goto cvode_failure;
    }
    if (max_order > 0) {
        retval = CVodeSetMaxOrd(cvode_mem, max_order);
        if (retval != CV_SUCCESS) goto cvode_failure;
    }

    retval = CVode(cvode_mem, (sunrealtype)t_final, y, &t_reached_sun, CV_NORMAL);
    t_reached = (double)t_reached_sun;

cvode_failure:
    (void)CVodeGetNumSteps(cvode_mem, &num_steps);
    (void)CVodeGetLastStep(cvode_mem, &last_step_sun);
    if (CVodeGetNumRhsEvals(cvode_mem, &num_rhs_evals) != CV_SUCCESS) num_rhs_evals = bridge.rhs_evals;
    (void)CVodeGetNumErrTestFails(cvode_mem, &num_error_test_fails);
    (void)CVodeGetNumNonlinSolvIters(cvode_mem, &num_nonlinear_iters);
    (void)CVodeGetNumNonlinSolvConvFails(cvode_mem, &num_nonlinear_conv_fails);
    (void)CVodeGetNumStepSolveFails(cvode_mem, &num_step_solve_fails);
    (void)CVodeGetLastOrder(cvode_mem, &last_order);
    last_step = (double)last_step_sun;

    if (tltm_cvode_values_are_finite(y_storage, n)) {
        memcpy(y_out, y_storage, (size_t)n * sizeof(double));
    }
    if (num_steps_out != NULL) *num_steps_out = (int)num_steps;
    if (last_step_out != NULL) *last_step_out = last_step;
    if (t_reached_out != NULL) *t_reached_out = t_reached;
    if (rhs_evals_out != NULL) *rhs_evals_out = tltm_cvode_long_to_int_nonnegative(num_rhs_evals);
    if (error_test_fails_out != NULL) *error_test_fails_out = tltm_cvode_long_to_int_nonnegative(num_error_test_fails);
    if (nonlinear_iters_out != NULL) *nonlinear_iters_out = tltm_cvode_long_to_int_nonnegative(num_nonlinear_iters);
    if (nonlinear_conv_fails_out != NULL) *nonlinear_conv_fails_out = tltm_cvode_long_to_int_nonnegative(num_nonlinear_conv_fails);
    if (step_solve_fails_out != NULL) *step_solve_fails_out = tltm_cvode_long_to_int_nonnegative(num_step_solve_fails);
    if (last_order_out != NULL) *last_order_out = last_order;

    if (retval == CV_SUCCESS) {
        status = TLTM_CVODE_STATUS_SUCCESS;
    } else if (retval == CV_TOO_MUCH_WORK) {
        status = TLTM_CVODE_STATUS_MAX_STEPS;
    } else {
        status = TLTM_CVODE_STATUS_INVALID;
    }

cleanup:
    if (cvode_mem != NULL) CVodeFree(&cvode_mem);
    if (nls != NULL) (void)SUNNonlinSolFree(nls);
    if (y != NULL) N_VDestroy_Serial(y);
    if (sunctx != NULL) (void)SUNContext_Free(&sunctx);
    free(y_storage);

    return status;
}

#else

int tltm_sundials_cvode_available(void)
{
    return 0;
}

int tltm_sundials_cvode_integrate(int n,
                                  const double *y0,
                                  double t_final,
                                  double abs_tol,
                                  double rel_tol,
                                  int max_num_steps,
                                  int fixedpoint_m,
                                  int max_order,
                                  double *y_out,
                                  int *num_steps_out,
                                  double *last_step_out,
                                  double *t_reached_out,
                                  int *rhs_evals_out,
                                  int *error_test_fails_out,
                                  int *nonlinear_iters_out,
                                  int *nonlinear_conv_fails_out,
                                  int *step_solve_fails_out,
                                  int *last_order_out,
                                  void *user_ctx,
                                  tltm_cvode_rhs_cb rhs_cb)
{
    (void)n;
    (void)y0;
    (void)t_final;
    (void)abs_tol;
    (void)rel_tol;
    (void)max_num_steps;
    (void)fixedpoint_m;
    (void)max_order;
    (void)y_out;
    (void)user_ctx;
    (void)rhs_cb;
    if (num_steps_out != NULL) *num_steps_out = 0;
    if (last_step_out != NULL) *last_step_out = 0.0;
    if (t_reached_out != NULL) *t_reached_out = 0.0;
    if (rhs_evals_out != NULL) *rhs_evals_out = 0;
    if (error_test_fails_out != NULL) *error_test_fails_out = 0;
    if (nonlinear_iters_out != NULL) *nonlinear_iters_out = 0;
    if (nonlinear_conv_fails_out != NULL) *nonlinear_conv_fails_out = 0;
    if (step_solve_fails_out != NULL) *step_solve_fails_out = 0;
    if (last_order_out != NULL) *last_order_out = 0;
    return TLTM_CVODE_STATUS_UNAVAILABLE;
}

#endif
