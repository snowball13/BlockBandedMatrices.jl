### This code is modified from Julia v0.6 Base
#  License is MIT: https://julialang.org/license

# Level 2
## mv
### gemv
for (fname, elty) in ((:dgemv_,:Float64),
                      (:sgemv_,:Float32),
                      (:zgemv_,:ComplexF64),
                      (:cgemv_,:ComplexF32))
    @eval begin
         #SUBROUTINE DGEMV(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
         #*     .. Scalar Arguments ..
         #      DOUBLE PRECISION ALPHA,BETA
         #      INTEGER INCX,INCY,LDA,M,N
         #      CHARACTER TRANS
         #*     .. Array Arguments ..
         #      DOUBLE PRECISION A(LDA,*),X(*),Y(*)
         function gemv!(trans::Char, alpha::($elty), A::AbstractVecOrMat{$elty}, X::AbstractVector{$elty}, beta::($elty), Y::AbstractVector{$elty})
             m,n = size(A,1),size(A,2)
             if trans == 'N' && (length(X) != n || length(Y) != m)
                 throw(DimensionMismatch("A has dimensions $(size(A)), X has length $(length(X)) and Y has length $(length(Y))"))
             elseif trans == 'C' && (length(X) != m || length(Y) != n)
                 throw(DimensionMismatch("the adjoint of A has dimensions $n, $m, X has length $(length(X)) and Y has length $(length(Y))"))
             elseif trans == 'T' && (length(X) != m || length(Y) != n)
                 throw(DimensionMismatch("the transpose of A has dimensions $n, $m, X has length $(length(X)) and Y has length $(length(Y))"))
             end
             ccall((@blasfunc($fname), libblas), Cvoid,
                 (Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ref{$elty},
                  Ptr{$elty}, Ref{BlasInt}, Ptr{$elty}, Ref{BlasInt},
                  Ref{$elty}, Ptr{$elty}, Ref{BlasInt}),
                  trans, size(A,1), size(A,2), alpha,
                  A, max(1,stride(A,2)), X, stride(X,1),
                  beta, Y, stride(Y,1))
             Y
         end
    end
end

for (gemm, elty) in
        ((:dgemm_,:Float64),
         (:sgemm_,:Float32),
         (:zgemm_,:ComplexF64),
         (:cgemm_,:ComplexF32))
    @eval begin
             # SUBROUTINE DGEMM(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
             # *     .. Scalar Arguments ..
             #       DOUBLE PRECISION ALPHA,BETA
             #       INTEGER K,LDA,LDB,LDC,M,N
             #       CHARACTER TRANSA,TRANSB
             # *     .. Array Arguments ..
             #       DOUBLE PRECISION A(LDA,*),B(LDB,*),C(LDC,*)
        function gemm!(transA::Char, transB::Char, alpha::($elty), A::AbstractVecOrMat{$elty}, B::AbstractVecOrMat{$elty}, beta::($elty), C::AbstractVecOrMat{$elty})
#           if any([stride(A,1), stride(B,1), stride(C,1)] .!= 1)
#               error("gemm!: BLAS module requires contiguous matrix columns")
#           end  # should this be checked on every call?
            m = size(A, transA == 'N' ? 1 : 2)
            ka = size(A, transA == 'N' ? 2 : 1)
            kb = size(B, transB == 'N' ? 1 : 2)
            n = size(B, transB == 'N' ? 2 : 1)
            if ka != kb || m != size(C,1) || n != size(C,2)
                throw(DimensionMismatch("A has size ($m,$ka), B has size ($kb,$n), C has size $(size(C))"))
            end
            ccall((@blasfunc($gemm), libblas), Cvoid,
                (Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt},
                 Ref{BlasInt}, Ref{$elty}, Ptr{$elty}, Ref{BlasInt},
                 Ptr{$elty}, Ref{BlasInt}, Ref{$elty}, Ptr{$elty},
                 Ref{BlasInt}),
                 transA, transB, m, n,
                 ka, alpha, A, max(1,stride(A,2)),
                 B, max(1,stride(B,2)), beta, C,
                 max(1,stride(C,2)))
            C
        end
    end
end


## (TR) triangular matrices: solver and inverse
for (trtri, trtrs, elty) in
    ((:dtrtri_,:dtrtrs_,:Float64),
     (:strtri_,:strtrs_,:Float32),
     (:ztrtri_,:ztrtrs_,:ComplexF64),
     (:ctrtri_,:ctrtrs_,:ComplexF32))
    @eval begin
        #     SUBROUTINE DTRTRI( UPLO, DIAG, N, A, LDA, INFO )
        #*     .. Scalar Arguments ..
        #      CHARACTER          DIAG, UPLO
        #      INTEGER            INFO, LDA, N
        #     .. Array Arguments ..
        #      DOUBLE PRECISION   A( LDA, * )
        function trtri!(uplo::Char, diag::Char, A::AbstractMatrix{$elty})
            chkstride1(A)
            n = checksquare(A)
            chkuplo(uplo)
            chkdiag(diag)
            lda = max(1,stride(A, 2))
            info = Ref{BlasInt}()
            ccall((@blasfunc($trtri), liblapack), Cvoid,
                  (Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ptr{$elty}, Ref{BlasInt},
                   Ptr{BlasInt}),
                  uplo, diag, n, A, lda, info)
            chklapackerror(info[])
            A
        end

        #      SUBROUTINE DTRTRS( UPLO, TRANS, DIAG, N, NRHS, A, LDA, B, LDB, INFO )
        # *     .. Scalar Arguments ..
        #       CHARACTER          DIAG, TRANS, UPLO
        #       INTEGER            INFO, LDA, LDB, N, NRHS
        # *     .. Array Arguments ..
        #       DOUBLE PRECISION   A( LDA, * ), B( LDB, * )
        function trtrs!(uplo::Char, trans::Char, diag::Char,
                        A::AbstractMatrix{$elty}, B::AbstractVecOrMat{$elty})
            chktrans(trans)
            chkdiag(diag)
            chkstride1(A)
            n = checksquare(A)
            chkuplo(uplo)
            if n != size(B,1)
                throw(DimensionMismatch("B has first dimension $(size(B,1)) but needs $n"))
            end
            info = Ref{BlasInt}()
            ccall((@blasfunc($trtrs), liblapack), Cvoid,
                  (Ref{UInt8}, Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt},
                   Ptr{$elty}, Ref{BlasInt}, Ptr{$elty}, Ref{BlasInt}, Ptr{BlasInt}),
                  uplo, trans, diag, n, size(B,2), A, max(1,stride(A,2)),
                  B, max(1,stride(B,2)), info)
            chklapackerror(info[])
            B
        end
    end
end
