# module SimpleMCMC

	# import Base.*

	# export                                  # types
	#     simpleMCMC,
	#     expexp,
	#     parseParams

	####################################################################################

	function expexp(ex::Expr, ident...)
		ident = (length(ident)==0 ? 0 : ident[1])::Integer
		println(rpad("", ident, " "), ex.head, " -> ")
		for e in ex.args
			typeof(e)==Expr ? expexp(e, ident+3) : println(rpad("", ident+3, " "), "[", typeof(e), "] : ", e)
		end
	end

	####################################################################

	function parseModel(ex)
		if typeof(ex) == Expr
			if ex.args[1]== :~
				ex = :(acc = acc + sum(logpdf($(ex.args[3]), $(ex.args[2]))))
			else 
				ex = Expr(ex.head, { parseModel(e) for e in ex.args}, Any)
			end
		end
		ex
	end

	# function mlog_normal(x::Float64, sigma::Float64) 
	# 	tmp = x / sigma
	# 	-tmp*tmp 
	# end
	# function mlog_normal(x::Vector{Float64}, sigma::Float64) 
	# 	tmp = x / sigma
	# 	- sum(tmp .* tmp)
	# end

	###############################################################
# params
	function parseParams(ex::Expr)
		println(ex.head, " -> ")
		@assert contains([:block, :tuple], ex.head)
		index = 1
		assigns = {}
		for e in ex.args
			if e.head == :(::)
				@assert typeof(e.args[1]) == Symbol
				@assert typeof(e.args[2]) == Expr
				e2 = e.args[2]
				if e2.args[1] == :scalar
					push(assigns, :($(e.args[1]) = beta[$index]))
					index += 1
				elseif typeof(e2.args[1]) == Expr
					e3 = e2.args[1].args
					if e3[1] == :vector
						nb = eval(e3[2])
						push(assigns, :($(e.args[1]) = beta[$index:$(nb+index-1)]))
						index += nb
					end
				end
			end
		end

		(index-1, Expr(:block, assigns, Any))
	end

	###############################################################
	function simpleMCMC7(model::Expr, params::Expr, steps::Integer, scale::Real)
		# steps = 10
		# scale = 0.1
		local beta
		local __lp
		local nbeta

		model2 = parseModel(model)
		println(model2)
		(nbeta, parmap) = parseParams(params)
		println(parmap)

		beta = ones(nbeta)

		println("beta : ", beta, size(beta))

		eval(parmap)
		println("sigma :", sigma)
		println("vars : ", vars)

		__lp = 0.0
		eval(model2)
		println("__lp :", __lp)

		samples = zeros(Float64, (steps, 2+nbeta))

		loop = quote
		 	for __i in 1:steps
				oldbeta, beta = beta, beta + randn(nbeta) * scale

				$parmap # eval(parmap)
		 		old__lp, __lp = __lp, 0.0

				$model2  # eval(model2)
				if rand() > exp(__lp - old__lp)
					__lp, beta = old__lp, oldbeta
				end
				samples[__i, :] = vcat(__lp, beta)
			end
		end
		println(loop)

		eval(loop)
		samples
	end

	function simpleMCMC9(model::Expr, params::Expr, steps::Integer, scale::Real)
		# steps = 10
		# scale = 0.1
		local beta
		local nbeta

		model2 = parseModel(model)
		println(model2)
		(nbeta, parmap) = parseParams(params)
		println(parmap)

		beta = ones(nbeta)
		println("beta : ", beta, size(beta))

		eval(quote
			function loop(beta::Vector{Float64})
				local acc

				$parmap

				acc = 0.0

				$model2

				return(acc)
			end
		end)
		__lp = loop(beta)
		println("loop 1: ", __lp)

		samples = zeros(Float64, (steps, 2+nbeta))

		__lp = -Inf
	 	for __i in 1:steps
			oldbeta, beta = beta, beta + randn(nbeta) * scale

	 		old__lp, __lp = __lp, loop(beta)

			if rand() > exp(__lp - old__lp)
				__lp, beta = old__lp, oldbeta
			end
			samples[__i, :] = vcat(__lp, (old__lp != __lp), beta)
		end

		samples
	end

	function simpleMCMC10(model::Expr, params::Expr, steps::Integer)
		# steps = 10
		# scale = 0.1
		local beta, nbeta
		local jump, S

		model2 = parseModel(model)
		println(model2)
		(nbeta, parmap) = parseParams(params)
		println(parmap)

		beta = ones(nbeta)
		println("beta : ", beta, size(beta))

		eval(quote
			function loop(beta::Vector{Float64})
				local acc
				$parmap
				acc = 0.0
				$model2
				return(acc)
			end
		end)

		__lp = loop(beta)
		println("loop 1: ", __lp)

		samples = zeros(Float64, (steps, 2+nbeta))
		__lp = -Inf
		S = eye(nbeta)
	 	for i in 1:steps	 		
			jump = 0.1 * randn(nbeta)
			oldbeta, beta = beta, beta + S * jump
			println((S * jump)[1:3])

	 		old__lp, __lp = __lp, loop(beta)
	 		alpha = min(1, exp(__lp - old__lp))
			if rand() > exp(__lp - old__lp)
				__lp, beta = old__lp, oldbeta
			end
			samples[i, :] = vcat(__lp, (old__lp != __lp), beta)

			eta = min(1, nbeta*i^(-2/3))
			SS = (jump * jump') * ((1 / (jump' * jump)) * eta * (alpha - 0.234))[1,1]
			SS = S * (eye(nbeta) + SS) * S'
			S = lu(SS)[1]
		end

		samples
	end


# end
