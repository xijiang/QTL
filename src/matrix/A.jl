"""
    function kinship(ped, i, j)
---
This function is handy if just to calculate relationship of a few (pairs of) ID.
It can also speed up by adding `Thread.@threads` before your pair loop.
"""
function kinship(ped, i, j)
    (i == 0 || j == 0) && return 0
    ipa, ima = ped[i, :]          # used both for below and the last
    i == j && (return 1 + .5kinship(ped, ipa, ima))
    if i < j
        jpa, jma = ped[j, :]
        return .5(kinship(ped, i, jpa) + kinship(ped, i, jma))
    end
    return .5(kinship(ped, j, ipa) + kinship(ped, j, ima))
end

"""
    function kinship(ped, i::Int, j::Int, dic::Dict{Tuple{Int, Int}, Float64})
Recursive kinship calculation with kinship of ID pair `(i, j)`
stored in dictionary `dic`.
The memory usage may be bigger than Meuwissen and Luo 1992, or Quaas 1995.
The speed is however standable.
The recursive algorithm is also easy to understand.
"""
function kinship(ped, i::Int, j::Int, dic::Dict{Tuple{Int, Int}, Float64})
    (i == 0 || j == 0) && return 0
    ip, im = ped[i, :]
    if i == j
        haskey(dic, (i, i)) || (dic[(i, i)] = 1 + .5kinship(ped, ip, im, dic))
        return dic[(i, i)]
    end
    if i < j
        jp, jm = ped[j, :]
        haskey(dic, (i, jp)) || (dic[(i, jp)] = kinship(ped, i, jp, dic))
        haskey(dic, (i, jm)) || (dic[(i, jm)] = kinship(ped, i, jm, dic))
        return .5(dic[(i, jp)] + dic[(i, jm)])
    end
    return .5(kinship(ped, j, ip, dic) + kinship(ped, j, im, dic))
end

"""
    function ped_F(ped; force = false)
- When column `:F` is not in DataFrame `ped`, this function calculate
inbreeding coefficients of every ID, and add a `:F` column in `ped`.
- If `:F` exists, and `force = true`, drop `:F` from `ped` and do above.
- Or do nothing.
"""
function ped_F(ped; force = false)
    if "F" ∈ names(ped)
        force ? select!(ped, Not([:F])) : return
    end
    N = nrow(ped)
    F = zeros(N)
    dic = Dict{Tuple{Int, Int}, Float64}()
    for i in 1:N
        F[i] = kinship(ped, i, i, dic) - 1
    end
    ped.F = F
end

"""
    function D4A(ped; inverse = false)
Given a sorted and recoded pedigree, this function return the `D` diagonal matrix for `A`
matrix calculation.
"""
function D4A(ped; inverse = false)
    N = nrow(ped)
    D = zeros(N)
    
end

"""
    function _D4A_ni(ped; inverse = false)
Construct a `D` diagonal matrix for `A` related calculation.
This one is for test only, and is hence internal.
"""
function _D4A_ni(ped; inverse = false)
    D = ones(nrow(ped))
    for (i, (pa, ma, ..)) in enumerate(eachrow(ped))
        pa > 0 && (D[i] -= .25)
        ma > 0 && (D[i] -= .25)
    end
    inverse && (D = 1 ./ D)
    Diagnal(D)
end

"""
    function _pushRCV!(R, C, V, r, c, v)
Push a value row, column, and value into vector `R`, `C` and `V`.
The vectors are later to be used to construct a sparse matrix.
"""
function _pushRCV!(R, C, V, r, c, v)
    push!(R, r)
    push!(C, c)
    push!(V, v)
end

"""
    function T4AI(ped)
Give a pedigree DataFrame, with its first 2 column as `pa`, and `ma`,
this function return the T matrix used for A⁻¹ calculation.
"""
function T4AI(ped)
    N = nrow(ped)
    # R, C, V: row, column and value specifying values in a sparse matrix
    # 3N are enough, as diagonal → N, all parents known → another 2N.
    R, C, V = Int[], Int[], Float64[]
    for (id, (pa, ma, ..)) in enumerate(eachrow(ped))
        pa > 0 && _pushRCV!(R, C, V, id, pa, -.5)
        ma > 0 && _pushRCV!(R, C, V, id, ma, -.5)
        _pushRCV!(R, C, V, id, id, 1.)
    end
    T = sparse(R, C, V)
end

function T4A(ped; m = 1000)
    N = nrow(ped)
    N > m && error("Pedigree size ($N > $m), too big")
    T = zeros(N, N) + I(N)
    for (i, (pa, ma, ..)) in enumerate(eachrow(ped))
        if pa > 0
            for j in 1:i-1
                T[i, j] += .5T[pa, j]
            end
        end
        if ma > 0
            for j in 1:i-1
                T[i, j] += .5T[ma, j]
            end
        end
    end
    T     
end

"""
    function A(ped; m = 1000)
Given a pedigree `ped`,
this function returns a full numerical relationship matrix, `A`.
This function is better for small pedigrees, and for demonstration only.
The maximal matrix size is thus limited to 1000.
One can try to set `m` to a bigger value if RAM is enough.
"""
function A(ped; m = 1000)
    N = nrow(ped)
    N > m && error("Pedigree size ($N > $m) too big")
    A = zeros(N, N) + I(N)
    for (i, (pa, ma, ..)) in enumerate(eachrow(ped))
        pa * ma ≠ 0 && (A[i, i] += .5A[pa, ma])
        for j in 1:i-1
            pa ≠ 0 && (A[i, j]  = 0.5A[j, pa])
            ma ≠ 0 && (A[i, j] += 0.5A[j, ma])
            A[j, i] = A[i, j]
        end
    end
    A
end

"""
    function A(T, D, range)
Construct sub matrix of `A` of `range` with `T`, and `D`.
"""
function A(T, D, range)
end

"""
    function Ai(ped)
Given a pedigree `ped`, this function return a sparse matrix of `A⁻¹`,
where `A` is the numerical relationship matrix.
"""
function Ai(ped)
    T = T4AI(ped)
    D = D4A(ped, inverse = true)
    T'D*T
end
