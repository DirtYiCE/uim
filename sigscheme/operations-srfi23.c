/*===========================================================================
 *  FileName : operations-srfi23.c
 *  About    : srfi23 Error reporting mechanism
 *
 *  Copyright (C) 2005      by Kazuki Ohta (mover@hct.zaq.ne.jp)
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *  3. Neither the name of authors nor the names of its contributors
 *     may be used to endorse or promote products derived from this software
 *     without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS
 *  IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 *  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 *  PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR
 *  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 *  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 *  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 *  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *  =========================================================================*/
/*=======================================
  System Include
=======================================*/
#include <stdlib.h>

/*=======================================
  Local Include
=======================================*/
#include "sigscheme.h"
#include "sigschemeinternal.h"

/*=======================================
  File Local Struct Declarations
=======================================*/

/*=======================================
  File Local Macro Declarations
=======================================*/

/*=======================================
  Variable Declarations
=======================================*/

/*=======================================
  File Local Function Declarations
=======================================*/

/*=======================================
  Function Implementations
=======================================*/
void SigScm_Initialize_SRFI23(void)
{
    /*=======================================================================
      SRFI-23 Procedure
    =======================================================================*/
#if SCM_USE_REGISTER_TABLE
    REGISTER_FUNC_TABLE(srfi23_func_info_table);
#else /* SCM_USE_REGISTER_TABLE */
    Scm_RegisterProcedureVariadic1("error", ScmOp_SRFI23_error);
#endif
}

/*=============================================================================
  SRFI23 : Error reporting mechanism
=============================================================================*/
ScmObj ScmOp_SRFI23_error(ScmObj reason, ScmObj args)
{
    ScmObj arg = SCM_FALSE;
    DECLARE_FUNCTION("error", ProcedureVariadic1);

    ASSERT_STRINGP(reason);
    
    if (SigScm_DebugCategories() & SCM_DBG_ERRMSG) {
        SigScm_ShowErrorHeader();
        SigScm_DisplayToPort(scm_current_error_port, reason);

        /* show each obj */
        for (; !NULLP(args); args = CDR(args)) {
            arg = CAR(args);
            SigScm_ErrorPrintf(" ");
#if SCM_USE_SRFI38
            SigScm_WriteToPortWithSharedStructure(scm_current_error_port, arg);
#else
            SigScm_WriteToPort(scm_current_error_port, arg);
#endif
        }

        SigScm_ErrorNewline();
    }

    Scm_ThrowException(args);
    /* NOTREACHED */
    return SCM_UNDEF;
}
