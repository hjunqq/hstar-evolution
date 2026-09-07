/*
 * gidpost_stub.c - Empty C stub implementations for GiD post-processing library.
 *
 * Provides link-time symbols for all GiD C functions referenced via BIND(C)
 * in gidpost.F90. These stubs are for linking purposes only on platforms
 * where the real GiD library is not available.
 *
 * All Fortran BIND(C) types (GiD_PostMode, GiD_Dimension, GiD_ElementType,
 * GiD_ResType, GiD_ResLoc, GiD_File) are single-member structs containing
 * one int, so they are passed as int by value in the C ABI.
 */

#include <stddef.h>  /* for NULL */

/* --------------------------------------------------------------------------
 * Global routines
 * -------------------------------------------------------------------------- */

void GiD_PostInit(void) {}
void GiD_PostDone(void) {}

/* --------------------------------------------------------------------------
 * Mesh routines
 * -------------------------------------------------------------------------- */

void GiD_OpenPostMeshFile(const char *filename, int postmode) {}
int  GiD_fOpenPostMeshFile(const char *filename, int postmode) { return 0; }

void GiD_ClosePostMeshFile(void) {}
void GiD_fClosePostMeshFile(int fd) {}

void GiD_BeginMeshGroup(const char *label) {}
void GiD_fBeginMeshGroup(int fd, const char *label) {}

void GiD_EndMeshGroup(void) {}
void GiD_fEndMeshGroup(int fd) {}

void GiD_MeshUnit(const char *unit_name) {}
void GiD_fMeshUnit(int fd, const char *unit_name) {}

void GiD_BeginMesh(const char *label, int dim, int elemtype, int nnode) {}
void GiD_fBeginMesh(int fd, const char *label, int dim, int elemtype, int nnode) {}

void GiD_BeginMeshColor(const char *label, int dim, int elemtype, int nnode,
                        double red, double green, double blue) {}
void GiD_fBeginMeshColor(int fd, const char *label, int dim, int elemtype, int nnode,
                         double red, double green, double blue) {}

void GiD_EndMesh(void) {}
void GiD_fEndMesh(int fd) {}

void GiD_BeginCoordinates(void) {}
void GiD_fBeginCoordinates(int fd) {}

void GiD_EndCoordinates(void) {}
void GiD_fEndCoordinates(int fd) {}

void GiD_WriteCoordinates2D(int id, double x, double y) {}
void GiD_fWriteCoordinates2D(int fd, int id, double x, double y) {}

void GiD_WriteCoordinates(int id, double x, double y, double z) {}
void GiD_fWriteCoordinates(int fd, int id, double x, double y, double z) {}

void GiD_BeginElements(void) {}
void GiD_fBeginElements(int fd) {}

void GiD_EndElements(void) {}
void GiD_fEndElements(int fd) {}

void GiD_WriteElement(int id, const int *conec) {}
void GiD_fWriteElement(int fd, int id, const int *conec) {}

void GiD_WriteElementMat(int id, const int *conec) {}
void GiD_fWriteElementMat(int fd, int id, const int *conec) {}

void GiD_WriteCircle(int id, int conec, double radius,
                     double normal_x, double normal_y, double normal_z) {}
void GiD_fWriteCircle(int fd, int id, int conec, double radius,
                      double normal_x, double normal_y, double normal_z) {}

void GiD_WriteCircleMat(int id, int conec, double radius,
                        double normal_x, double normal_y, double normal_z, int material) {}
void GiD_fWriteCircleMat(int fd, int id, int conec, double radius,
                         double normal_x, double normal_y, double normal_z, int material) {}

void GiD_WriteSphere(int id, int conec, double radius) {}
void GiD_fWriteSphere(int fd, int id, int conec, double radius) {}

void GiD_WriteSphereMat(int id, int conec, double radius, int material) {}
void GiD_fWriteSphereMat(int fd, int id, int conec, double radius, int material) {}

/* --------------------------------------------------------------------------
 * Results routines
 * -------------------------------------------------------------------------- */

void GiD_OpenPostResultFile(const char *filename, int postmode) {}
int  GiD_fOpenPostResultFile(const char *filename, int postmode) { return 0; }

void GiD_ClosePostResultFile(void) {}
void GiD_fClosePostResultFile(int fd) {}

void GiD_BeginGaussPoint(const char *label, int elemtype, const char *meshname,
                         int ngauss, int nodeincluded, int internalcoord) {}
void GiD_fBeginGaussPoint(int fd, const char *label, int elemtype, const char *meshname,
                          int ngauss, int nodeincluded, int internalcoord) {}

void GiD_EndGaussPoint(void) {}
void GiD_fEndGaussPoint(int fd) {}

void GiD_WriteGaussPoint2D(double x, double y) {}
void GiD_fWriteGaussPoint2D(int fd, double x, double y) {}

void GiD_WriteGaussPoint3D(double x, double y, double z) {}
void GiD_fWriteGaussPoint3D(int fd, double x, double y, double z) {}

void GiD_BeginRangeTable(const char *label) {}
void GiD_fBeginRangeTable(int fd, const char *label) {}

void GiD_EndRangeTable(void) {}
void GiD_fEndRangeTable(int fd) {}

void GiD_WriteMinRange(double minvalue, const char *label) {}
void GiD_fWriteMinRange(int fd, double minvalue, const char *label) {}

void GiD_WriteRange(double minvalue, double maxvalue, const char *label) {}
void GiD_fWriteRange(int fd, double minvalue, double maxvalue, const char *label) {}

void GiD_WriteMaxRange(double maxvalue, const char *label) {}
void GiD_fWriteMaxRange(int fd, double maxvalue, const char *label) {}

/* BeginScalarResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp */
void GiD_BeginScalarResult(const char *Result, const char *Analysis, double Step,
                           int Where, void *GaussPointsName, void *RangeTable,
                           void *Comp) {}

/* BeginVectorResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..4 */
void GiD_BeginVectorResult(const char *Result, const char *Analysis, double Step,
                           int Where, void *GaussPointsName, void *RangeTable,
                           void *Comp1, void *Comp2, void *Comp3, void *Comp4) {}

/* Begin2DMatResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..3 */
void GiD_Begin2DMatResult(const char *Result, const char *Analysis, double Step,
                          int Where, void *GaussPointsName, void *RangeTable,
                          void *Comp1, void *Comp2, void *Comp3) {}

/* Begin3DMatResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..6 */
void GiD_Begin3DMatResult(const char *Result, const char *Analysis, double Step,
                          int Where, void *GaussPointsName, void *RangeTable,
                          void *Comp1, void *Comp2, void *Comp3,
                          void *Comp4, void *Comp5, void *Comp6) {}

/* BeginPDMMatResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..4 */
void GiD_BeginPDMMatResult(const char *Result, const char *Analysis, double Step,
                           int Where, void *GaussPointsName, void *RangeTable,
                           void *Comp1, void *Comp2, void *Comp3, void *Comp4) {}

/* BeginMainMatResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..12 */
void GiD_BeginMainMatResult(const char *Result, const char *Analysis, double Step,
                            int Where, void *GaussPointsName, void *RangeTable,
                            void *Comp1, void *Comp2, void *Comp3, void *Comp4,
                            void *Comp5, void *Comp6, void *Comp7, void *Comp8,
                            void *Comp9, void *Comp10, void *Comp11, void *Comp12) {}

/* BeginLAResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Comp1..3 */
void GiD_BeginLAResult(const char *Result, const char *Analysis, double Step,
                       int Where, void *GaussPointsName, void *RangeTable,
                       void *Comp1, void *Comp2, void *Comp3) {}

/* BeginComplexScalarResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Re, Im */
void GiD_BeginComplexScalarResult(const char *Result, const char *Analysis, double Step,
                                  int Where, void *GaussPointsName, void *RangeTable,
                                  void *Re, void *Im) {}

/* BeginComplexVectorResult: Result, Analysis, Step, Where, GaussPointsName, RangeTable, Rex..Imz */
void GiD_BeginComplexVectorResult(const char *Result, const char *Analysis, double Step,
                                  int Where, void *GaussPointsName, void *RangeTable,
                                  void *Rex, void *Imx, void *Rey, void *Imy,
                                  void *Rez, void *Imz) {}

/* BeginResultHeader: Result, Analysis, Step, Type, Where, GaussPointsName */
void GiD_BeginResultHeader(const char *Result, const char *Analysis, double Step,
                           int Type, int Where, void *GaussPointsName) {}
void GiD_fBeginResultHeader(int fd, const char *Result, const char *Analysis, double Step,
                            int Type, int Where, void *GaussPointsName) {}

/* ScalarComp: Comp (C_PTR) */
void GiD_ScalarComp(void *Comp) {}

/* VectorComp: Comp1..4 (C_PTR) */
void GiD_VectorComp(void *Comp1, void *Comp2, void *Comp3, void *Comp4) {}

/* 2DMatrixComp: Comp1..3 (C_PTR) */
void GiD_2DMatrixComp(void *Comp1, void *Comp2, void *Comp3) {}

/* 3DMatrixComp: Comp1..6 (C_PTR) */
void GiD_3DMatrixComp(void *Comp1, void *Comp2, void *Comp3,
                      void *Comp4, void *Comp5, void *Comp6) {}

/* PDMComp: Comp1..4 (C_PTR) */
void GiD_PDMComp(void *Comp1, void *Comp2, void *Comp3, void *Comp4) {}

/* MainMatrixComp: Comp1..12 (C_PTR) */
void GiD_MainMatrixComp(void *Comp1, void *Comp2, void *Comp3, void *Comp4,
                        void *Comp5, void *Comp6, void *Comp7, void *Comp8,
                        void *Comp9, void *Comp10, void *Comp11, void *Comp12) {}

/* LAComponents: Comp1..3 (C_PTR) */
void GiD_LAComponents(void *Comp1, void *Comp2, void *Comp3) {}

/* ComplexScalarComp: Re, Im (C_PTR) */
void GiD_ComplexScalarComp(void *Re, void *Im) {}

/* ComplexVectorComp: Rex, Imx, Rey, Imy, Rez, Imz (C_PTR) */
void GiD_ComplexVectorComp(void *Rex, void *Imx, void *Rey, void *Imy,
                           void *Rez, void *Imz) {}

/* ResultUnit */
void GiD_ResultUnit(const char *unit_name) {}
void GiD_fResultUnit(int fd, const char *unit_name) {}

/* BeginResultGroup */
void GiD_BeginResultGroup(const char *Analysis, double Step, int Where,
                          void *GaussPointsName) {}
void GiD_fBeginResultGroup(int fd, const char *Analysis, double Step, int Where,
                           void *GaussPointsName) {}

/* ResultDescription */
void GiD_ResultDescription(const char *Result, int Type) {}
void GiD_fResultDescription(int fd, const char *Result, int Type) {}

/* BeginOnMeshGroup */
void GiD_BeginOnMeshGroup(const char *Label) {}
void GiD_fBeginOnMeshGroup(int fd, const char *Label) {}

void GiD_ResultValues(void) {}
void GiD_fResultValues(int fd) {}

void GiD_EndResult(void) {}
void GiD_fEndResult(int fd) {}

void GiD_EndOnMeshGroup(void) {}
void GiD_fEndOnMeshGroup(int fd) {}

void GiD_FlushPostFile(void) {}
void GiD_fFlushPostFile(int fd) {}

/* Write result values */
void GiD_WriteScalar(int id, double v) {}
void GiD_fWriteScalar(int fd, int id, double v) {}

void GiD_Write2DVector(int id, double x, double y) {}
void GiD_fWrite2DVector(int fd, int id, double x, double y) {}

void GiD_WriteVector(int id, double x, double y, double z) {}
void GiD_fWriteVector(int fd, int id, double x, double y, double z) {}

void GiD_WriteVectorModule(int id, double x, double y, double z, double mod) {}
void GiD_fWriteVectorModule(int fd, int id, double x, double y, double z, double mod) {}

void GiD_Write2DMatrix(int id, double Sxx, double Syy, double Sxy) {}
void GiD_fWrite2DMatrix(int fd, int id, double Sxx, double Syy, double Sxy) {}

void GiD_Write3DMatrix(int id, double Sxx, double Syy, double Szz,
                       double Sxy, double Syz, double Sxz) {}
void GiD_fWrite3DMatrix(int fd, int id, double Sxx, double Syy, double Szz,
                        double Sxy, double Syz, double Sxz) {}

void GiD_WritePlainDefMatrix(int id, double Sxx, double Syy, double Sxy, double Szz) {}
void GiD_fWritePlainDefMatrix(int fd, int id, double Sxx, double Syy, double Sxy, double Szz) {}

void GiD_WriteMainMatrix(int id, double Si, double Sii, double Siii,
                         double Vix, double Viy, double Viz,
                         double Viix, double Viiy, double Viiz,
                         double Viiix, double Viiiy, double Viiiz) {}
void GiD_fWriteMainMatrix(int fd, int id, double Si, double Sii, double Siii,
                          double Vix, double Viy, double Viz,
                          double Viix, double Viiy, double Viiz,
                          double Viiix, double Viiiy, double Viiiz) {}

void GiD_WriteLocalAxes(int id, double euler_1, double euler_2, double euler_3) {}
void GiD_fWriteLocalAxes(int fd, int id, double euler_1, double euler_2, double euler_3) {}

void GiD_WriteComplexScalar(int id, double Re, double Im) {}
void GiD_fWriteComplexScalar(int fd, int id, double Re, double Im) {}

void GiD_WriteComplexVector(int id, double Rex, double Imx, double Rey,
                            double Imy, double Rez, double Imz) {}
void GiD_fWriteComplexVector(int fd, int id, double Rex, double Imx, double Rey,
                             double Imy, double Rez, double Imz) {}

/* BeginResult: generic version with nComp and Comp pointer array */
void GiD_BeginResult(const char *Result, const char *Analysis, double Step,
                     int Type, int Where, void *GaussPointsName, void *RangeTable,
                     int nComp, void *Comp) {}
void GiD_fBeginResult(int fd, const char *Result, const char *Analysis, double Step,
                      int Type, int Where, void *GaussPointsName, void *RangeTable,
                      int nComp, void *Comp) {}

/* ResultComponents: nComp and Comp pointer array */
void GiD_ResultComponents(int nComp, void *Comp) {}
void GiD_fResultComponents(int fd, int nComp, void *Comp) {}
