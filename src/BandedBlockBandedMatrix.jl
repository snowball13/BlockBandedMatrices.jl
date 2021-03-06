

struct BandedBlockBandedLayout{T} <: AbstractBlockBandedInterface{T} end


struct BandedBlockBandedSizes
    block_sizes::BlockSizes{2}
    data_block_sizes::BlockSizes{2}
    l::Int
    u::Int
    λ::Int
    μ::Int
end


function BandedBlockBandedSizes(bs::BlockSizes{2}, l, u, λ, μ)
    # data matrix has row blocks all the same size but same column blocks
    # we access the cumul vec directly to reuse bs.cumul_sizes[2]
    d_bs = BlockSizes((BlockArrays._cumul_vec(fill(λ+μ+1, l+u+1)),bs.cumul_sizes[2]))
    BandedBlockBandedSizes(bs, d_bs, l, u, λ, μ)
end

BandedBlockBandedSizes(rows::AbstractVector{Int}, cols::AbstractVector{Int}, l, u, λ, μ) =
    BandedBlockBandedSizes(BlockSizes(rows,cols), l, u, λ, μ)


for Func in (:nblocks, :getindex, :blocksize, :global2blockindex, :unblock, :size, :globalrange)
    @eval begin
        $Func(B::BandedBlockBandedSizes) = $Func(B.block_sizes)
        $Func(B::BandedBlockBandedSizes, k) = $Func(B.block_sizes, k)
        $Func(B::BandedBlockBandedSizes, k, j) = $Func(B.block_sizes, k, j)
    end
end

convert(::Type{BlockBandedSizes}, B::BandedBlockBandedSizes) =
    BlockBandedSizes(B.block_sizes, B.l, B.u)

function check_data_sizes(data::AbstractBlockMatrix, B::BandedBlockBandedSizes)
    bs = data.block_sizes
    c_rows, c_cols = bs.cumul_sizes
    if length(c_rows) ≠ B.l + B.u + 2
        throw(ArgumentError("Data matrix must have number of row blocks equal to number of block bands"))
    end
    for k = 1:length(c_rows)-1
        if c_rows[k+1]-c_rows[k] ≠ B.λ + B.μ + 1
            throw(ArgumentError("Data matrix must have row block sizes equal to number of subblock bands"))
        end
    end
    if c_cols ≠ B.block_sizes.cumul_sizes[2]
        throw(ArgumentError("Data matrix must have same column blocks as matrix"))
    end
end


function _BandedBlockBandedMatrix end


# Represents a block banded matrix with banded blocks
#   similar to BandedMatrix{BandedMatrix{T}}
# Here the data is stored by blocks, in a way that is consistent with
# BandedMatrix
#

struct BandedBlockBandedMatrix{T} <: AbstractBlockBandedMatrix{T}
    data::PseudoBlockMatrix{T, Matrix{T}}
    block_sizes::BandedBlockBandedSizes

    l::Int  # block lower bandwidth
    u::Int  # block upper bandwidth
    λ::Int  # sub lower bandwidth
    μ::Int  # sub upper bandwidth

    global function _BandedBlockBandedMatrix(data::PseudoBlockMatrix{T}, block_sizes::BandedBlockBandedSizes) where T
        @boundscheck check_data_sizes(data, block_sizes)
        new{T}(data, block_sizes, block_sizes.l, block_sizes.u, block_sizes.λ, block_sizes.μ)
    end
end

@inline _BandedBlockBandedMatrix(data::AbstractMatrix, block_sizes::BandedBlockBandedSizes) =
    _BandedBlockBandedMatrix(PseudoBlockArray(data, block_sizes.data_block_sizes), block_sizes)

BandedBlockBandedMatrix{T}(::Uninitialized, block_sizes::BandedBlockBandedSizes) where T =
    _BandedBlockBandedMatrix(
        PseudoBlockArray{T}(uninitialized, block_sizes.data_block_sizes), block_sizes)

BandedBlockBandedMatrix{T}(::Uninitialized, dims::NTuple{2, AbstractVector{Int}},
                        lu::NTuple{2, Int}, λμ::NTuple{2, Int}) where T =
    BandedBlockBandedMatrix{T}(uninitialized, BandedBlockBandedSizes(dims..., lu..., λμ...))


# Auxiliary outer constructors
@inline _BandedBlockBandedMatrix(data::AbstractMatrix, dims::NTuple{2, AbstractVector{Int}},
                                         lu::NTuple{2, Int}, λμ::NTuple{2, Int}) =
    _BandedBlockBandedMatrix(data, BandedBlockBandedSizes(dims..., lu..., λμ...))


function convert(::Type{BandedBlockBandedMatrix{T}}, B::BandedMatrix) where T
    if isdiag(B)
        _BandedBlockBandedMatrix(copy(B.data), (ones(Int,size(B,1)),ones(Int,size(B,2))), (0,0), (0,0))
    else
        _BandedBlockBandedMatrix(copy(B.data), [size(B,1)], [size(B,2)], (0,0), (B.l,B.u))
    end
end

convert(::Type{BandedBlockBandedMatrix}, B::BandedMatrix) = convert(BandedBlockBandedMatrix{eltype(B)}, B)

function BandedBlockBandedMatrix{T}(Z::Zeros, dims::NTuple{2,AbstractVector{Int}},
                                    lu::NTuple{2,Int}, λμ::NTuple{2,Int}) where T
   if size(Z) ≠ sum.(dims)
       throw(DimensionMismatch())
   end

   bs = BandedBlockBandedSizes(dims..., lu..., λμ...)
   d_bs = bs.data_block_sizes
    _BandedBlockBandedMatrix(PseudoBlockArray(zeros(T, size(d_bs)), d_bs), bs)
end


function BandedBlockBandedMatrix{T}(E::Eye, dims::NTuple{2,AbstractVector{Int}},
                                    lu::NTuple{2,Int}, λμ::NTuple{2,Int}) where T
    if size(E) ≠ sum.(dims)
        throw(DimensionMismatch())
    end
    ret = BandedBlockBandedMatrix(Zeros{T}(E), dims, lu, λμ)
    ret[diagind(ret)] = one(T)
    ret
end

function BandedBlockBandedMatrix{T}(A::UniformScaling, dims::NTuple{2, AbstractVector{Int}},
                                    lu::NTuple{2,Int}, λμ::NTuple{2,Int}) where T
    ret = BandedBlockBandedMatrix(Zeros{T}(sum.(dims)), dims, lu, λμ)
    ret[diagind(ret)] = convert(T, A.λ)
    ret
end


BandedBlockBandedMatrix(A::Union{AbstractMatrix,UniformScaling},
                        dims::NTuple{2, AbstractVector{Int}},
                        lu::NTuple{2,Int}, λμ::NTuple{2,Int}) =
    BandedBlockBandedMatrix{eltype(A)}(A, dims, lu, λμ)



################################
# BandedBlockBandedMatrix Interface #
################################

memorylayout(::Type{BandedBlockBandedMatrix{T}}) where T = BandedBlockBandedLayout{T}()

isbandedblockbanded(_) = false
isbandedblockbanded(::BandedBlockBandedMatrix) = true

blockbandwidth(A::BandedBlockBandedMatrix, i::Int) = ifelse(i==1, A.l, A.u)
subblockbandwidth(A::BandedBlockBandedMatrix, i::Int) = ifelse(i==1, A.λ, A.μ)

isdiag(A::BandedBlockBandedMatrix) = A.λ == A.μ == A.l == A.u


################################
# AbstractBlockArray Interface #
################################

@inline nblocks(block_array::BandedBlockBandedMatrix) = nblocks(block_array.block_sizes)
@inline blocksize(block_array::BandedBlockBandedMatrix, i1::Int, i2::Int) = blocksize(block_array.block_sizes, (i1,i2))


zeroblock(A::BandedBlockBandedMatrix, K::Int, J::Int) =
    BandedMatrix(Zeros{eltype(A)}(blocksize(A, K, J)), (A.λ, A.μ))

@inline function getblock(A::BandedBlockBandedMatrix, K::Int, J::Int)
    @boundscheck blockcheckbounds(A, K, J)
    if -A.l ≤ J - K ≤ A.u
        convert(BandedMatrix, view(A, Block(K, J)))
    else
        zeroblock(A, K, J)
    end
end

# @inline function Base.getindex(block_arr::BlockArray{T,N}, blockindex::BlockIndex{N}) where {T,N}
#     @boundscheck checkbounds(block_arr.blocks, blockindex.I...)
#     @inbounds block = block_arr.blocks[blockindex.I...]
#     @boundscheck checkbounds(block, blockindex.α...)
#     @inbounds v = block[blockindex.α...]
#     return v
# end


###########################
# AbstractArray Interface #
###########################

# @inline function Base.similar(block_array::BandedBlockBandedMatrix{T}, ::Type{T2}) where {T,N,T2}
#     BlockArray(similar(block_array.blocks, Array{T2, N}), copy(block_array.block_sizes))
# end

Base.size(arr::BandedBlockBandedMatrix) =
    @inbounds return size(arr.block_sizes)


@inline function getindex(A::BandedBlockBandedMatrix, i::Int, j::Int)
    @boundscheck checkbounds(A, i, j)
    bi = global2blockindex(A.block_sizes, (i, j))
    @inbounds v = view(A, Block(bi.I))[bi.α...]
    return v
end

@inline function setindex!(A::BandedBlockBandedMatrix{T}, v, i::Int, j::Int) where T
    @boundscheck checkbounds(A, i, j)
    bi = global2blockindex(A.block_sizes, (i, j))
    V = view(A, Block(bi.I))
    @inbounds V[bi.α...] = convert(T, v)::T
    return v
end



######
# extra marrix routines
#####

function Base.fill!(A::BandedBlockBandedMatrix, x)
    !iszero(x) && throw(BandError(A))
    fill!(A.data, x)
    A
end

function Base.scale!(A::BandedBlockBandedMatrix, x::Number)
    scale!(A.data, x)
    A
end


function Base.scale!(x::Number, A::BandedBlockBandedMatrix)
    scale!(x, A.data)
    A
end


############
# Indexing #
############

# function _check_setblock!(block_arr::BlockArray{T, N}, v, block::NTuple{N, Int}) where {T,N}
#     for i in 1:N
#         if size(v, i) != blocksize(block_arr.block_sizes, i, block[i])
#             throw(DimensionMismatch(string("tried to assign $(size(v)) array to ", blocksize(block_arr, block...), " block")))
#         end
#     end
# end
#
#
@inline function setblock!(A::BandedBlockBandedMatrix, v, K::Int, J::Int)
    @boundscheck blockcheckbounds(A, K, J)

    @boundscheck (bandwidth(v, 1) > A.λ || bandwidth(v, 2) > A.μ) && throw(BandError())
    V = view(A, Block(K), Block(J))
    V .= v
    return A
end
#
# @propagate_inbounds function Base.setindex!(block_array::BlockArray{T, N}, v, block_index::BlockIndex{N}) where {T,N}
#     getblock(block_array, block_index.I...)[block_index.α...] = v
# end

########
# Misc #
########

# @generated function Base.Array(block_array::BlockArray{T, N, R}) where {T,N,R}
#     # TODO: This will fail for empty block array
#     return quote
#         block_sizes = block_array.block_sizes
#         arr = similar(block_array.blocks[1], size(block_array)...)
#         @nloops $N i i->(1:nblocks(block_sizes, i)) begin
#             block_index = @ntuple $N i
#             indices = globalrange(block_sizes, block_index)
#             arr[indices...] = getblock(block_array, block_index...)
#         end
#
#         return arr
#     end
# end
#
# @generated function Base.copy!(block_array::BlockArray{T, N, R}, arr::R) where {T,N,R <: AbstractArray}
#     return quote
#         block_sizes = block_array.block_sizes
#
#         @nloops $N i i->(1:nblocks(block_sizes, i)) begin
#             block_index = @ntuple $N i
#             indices = globalrange(block_sizes, block_index)
#             copy!(getblock(block_array, block_index...), arr[indices...])
#         end
#
#         return block_array
#     end
# end
#
# function Base.fill!(block_array::BlockArray, v)
#     for block in block_array.blocks
#         fill!(block, v)
#     end
# end


subblockbandwidths(A::BandedBlockBandedMatrix) = A.λ, A.μ
subblockbandwidth(A::BandedBlockBandedMatrix, k::Integer) = ifelse(k==1 , A.λ , A.μ)



##################
# BandedBlockBandedBlock
#
#   views of the blocks satisfy the BandedMatrix interface, and are memory-compatible
#   with BLASBandedMatrix.
##################

const BandedBlockBandedBlock{T} = SubArray{T,2,BandedBlockBandedMatrix{T},Tuple{BlockSlice1,BlockSlice1},false}



function inblockbands(V::BandedBlockBandedBlock)
    A = parent(V)
    K_sl, J_sl = parentindexes(V)
    K, J = K_sl.block, J_sl.block
    -A.l ≤ Int(J-K) ≤ A.u
end


######################################
# BandedMatrix interface  for Blocks #
######################################
@inline bandwidth(V::BandedBlockBandedBlock, k::Int) = ifelse(k == 1, parent(V).λ, parent(V).μ)



# gives the columns of parent(V).data that encode the block
blocks(V::BandedBlockBandedBlock)::Tuple{Int,Int} = Int(first(parentindexes(V)).block),
                                                    Int(last(parentindexes(V)).block)


function dataview(V::BandedBlockBandedBlock)
    A = parent(V)
    u = A.u
    K_sl, J_sl = parentindexes(V)
    K, J = K_sl.block, J_sl.block
    view(A.data, u + K - J + 1, J)
end


@inline function inbands_getindex(V::BandedBlockBandedBlock, k::Int, j::Int)
    A = parent(V)
    banded_getindex(dataview(V), A.λ, A.μ, k, j)
end

@inline function inbands_setindex!(V::BandedBlockBandedBlock, v, k::Int, j::Int)
    A = parent(V)
    banded_setindex!(dataview(V), A.λ, A.μ, v, k, j)
end

@propagate_inbounds function getindex(V::BandedBlockBandedBlock, k::Int, j::Int)
    @boundscheck checkbounds(V, k, j)
    A = parent(V)
    K,J = blocks(V)
    if -A.l ≤ J-K ≤ A.u
        inbands_getindex(V, k, j)
    else
        zero(eltype(V))
    end
end

@propagate_inbounds function setindex!(V::BandedBlockBandedBlock, v, k::Int, j::Int)
    @boundscheck checkbounds(V, k, j)
    A = parent(V)
    K,J = blocks(V)
    if -A.l ≤ J-K ≤ A.u
        inbands_setindex!(V, v, k, j)
    elseif iszero(v) # allow setindex for 0 datya
        v
    else
        throw(BandError(parent(V), J-K))
    end
end




function convert(::Type{BandedMatrix{T}}, V::BandedBlockBandedBlock) where {T}
    A = parent(V)
    _BandedMatrix(Matrix{T}(dataview(V)), size(V,1), A.λ, A.μ)
end

convert(::Type{BandedMatrix}, V::BandedBlockBandedBlock) = convert(BandedMatrix{eltype(V)}, V)




#############
# Linear algebra
#############


# BLAS structure
unsafe_convert(::Type{Ptr{T}}, V::BandedBlockBandedBlock{T}) where {T<:BlasFloat} =
    unsafe_convert(Ptr{T}, dataview(V))

@inline leadingdimension(V::BandedBlockBandedBlock) = stride(dataview(V), 2)
@inline memorylayout(::Type{BandedBlockBandedBlock{T}}) where T = BandedLayout{T}()

@banded BandedBlockBandedBlock
@banded_banded_linalg BandedBlockBandedBlock BandedSubBandedMatrix
