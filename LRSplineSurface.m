classdef LRSplineSurface < handle
% LRSplineSurface Matlab wrapper class for c++ LR-spline object
%     detailed description goes here

	properties(SetAccess = private, Hidden = false)
		p        % polynomial degree
		knots    % knot vectors
		cp       % control points
		w        % weights
		lines    % mesh lines, (u0,v0, u1,v1, m), where m is the multiplicity
		elements % fintite elements (u0, v0, u1, v1)
		support  % element to basis function support list
	end
	properties(SetAccess = private, Hidden = true)
		objectHandle;
	end

	methods
		function this = LRSplineSurface(n, p, varargin)
		% LRSplineSurface constructor, initialize a tensor product LRSplinSurface object
		% LRSplineSurface(n,p)
		% LRSplineSurface(n,p, knotU, knotV)
		% LRSplineSurface(n,p, knotU, knotV, controlpoint)
		% 
		%   parameters 
		%     n            - number of basis functions in each direction (2 components)
		%     p            - polynomial degree in each direction (2 components)
		%     knotU        - global open knot vector in u-direction (n(1)+p(1)+1 components)
		%     knotV        - global open knot vector in v-direction (n(2)+p(2)+1 components)
		%     controlpoint - list of control points (matrix of size dim x n(1)*n(2)), where dim is dimension in physical space

			% error check input
			if(nargin ~= 2 && nargin ~=4 && nargin ~= 5)
				throw(MException('LRSplineSurface:constructor',  'Error: Invalid number of arguments to LRSplineSurface constructor'));
			end
			if(length(p) ~=2 || length(n) ~=2)
				throw(MException('LRSplineSurface:constructor', 'Error: p and n should have 2 components'));
			end
			if(nargin > 3)
				for i=1:2
					if(~(size(varargin{i}) == [1, p(i)+n(i)+1]) )
						throw(MException('LRSplineSurface:constructor', 'Error: Knot vector should be a row vector of length p+n+1'));
					end
				end
			end
			if(nargin > 4)
				if(size(varargin{3},2) ~= n(1)*n(2))
					throw(MException('LRSplineSurface:constructor', 'Error: Control points should have n(1)*n(2) columns'));
				end
			end

			
			this.objectHandle = lrsplinesurface_interface('new', n,p, varargin{:});
			this.updatePrimitives();
		end


		function delete(this)
		% LRSplineSurface destructor clears object from memory
			lrsplinesurface_interface('delete', this.objectHandle);
		end


		function print(this)
			lrsplinesurface_interface('print', this.objectHandle);
		end


		function refine(this, indices, varargin)
		% REFINE performs local refinement of elements or basis functions
		% LRSplineSurface.refine(indices)
		% LRSplineSurface.refine(indices, 'elements')
		% LRSplineSurface.refine(indices, 'basis')
		%
		%   parameters:
		%     indices - index of the basis function or elements to refine
		%   returns
		%     none
			if(nargin > 2)
				if(strcmp(varargin{1}, 'elements'))
					lrsplinesurface_interface('refine_elements', this.objectHandle, indices);
				elseif(strcmp(varargin{1}, 'basis'))
					lrsplinesurface_interface('refine_basis', this.objectHandle, indices);
				else
					throw(MException('LRSplineSurface:refine',  'Error: Unknown refine parameter'));
				end
			else 
				lrsplinesurface_interface('refine_basis', this.objectHandle, indices);
			end
			this.updatePrimitives();
		end


		function x = point(this, u, v)
		% POINT evaluates the mapping from parametric to physical space
		% x = LRSplineSurface.point(u,v)
		%
		%   parameters:
		%     u - first parametric coordinate
		%     v - second parametric coordinate
		%   returns
		%     the parametric point mapped to physical space
			x = lrsplinesurface_interface('point', this.objectHandle, [u,v]);
		end


		function N = computeBasis(this, u, v, varargin)
		% computeBasis evaluates all basis functions at a given parametric point, as well as their derivatives
		% N = LRSplineSurface.computeBasis(u, v)
		% N = LRSplineSurface.computeBasis(u, v, derivs)
		%
		%   parameters:
		%     u      - first parametric coordinate
		%     v      - second parametric coordinate
		%     derivs - number of derivatives (greater or equal to 0)
		%   returns
		%     the value of all nonzero basis functions at a given point
		%     in case of derivatives, a cell is returned with all derivatives requested
			N = lrsplinesurface_interface('compute_basis', this.objectHandle, [u, v], varargin{:});
		end


		function C = getBezierExtraction(this, element)
		% getBezierExtraction returns the bezier extraction matrix for this element
		% C = LRSplineSurface.getBezierExtraction(element)
		%
		%   parameters:
		%     element - global index to the element 
		%   returns
		%     a matrix with as many rows as there is active basis functions and (p(1)+1)*(p(2)+1) columns
			C = lrsplinesurface_interface('get_bezier_extraction', this.objectHandle, element);
		end


		function iel = getElementContaining(this, u,v)
		% getElementContaining returns the index of the element containing the parametric point (u,v)
		% iel = getElementContaining(u,v)
		%
		%   parameters:
		%     u - first parametric coordinate
		%     v - second parametric coordinate
		%   returns
		%     index to the element containint this parametric point
			iel = lrsplinesurface_interface('get_element_containing', this.objectHandle, [u,v]);
		end


		function basis = getEdge(this, edge)
			if(edge == 1)
				umin = min(this.knots(:,1));
				basis = find(this.knots(:, this.p(1)+1) == umin);
			elseif(edge == 2)
				umax = max(this.knots(:,this.p(1)+2));
				basis = find(this.knots(:, 2) == umax);
			elseif(edge == 3)
				vmin = min(this.knots(:,this.p(1)+3));
				basis = find(this.knots(:, end-1) == vmin);
			elseif(edge == 4)
				vmax = max(this.knots(:,end));
				basis = find(this.knots(:, this.p(1)+4) == vmax);
			else
				throw(MException('LRSplineSurface:getEdge',  'Error: Invalid edge enumeration'));
			end
		end

		function H = plot(this, varargin)
			nPtsPrLine = 41;
			nLines     = size(this.lines, 1);
			x = zeros(nPtsPrLine, nLines);
			y = zeros(nPtsPrLine, nLines);
			for i=1:nLines
				u = linspace(this.lines(i,1), this.lines(i,3), nPtsPrLine);
				v = linspace(this.lines(i,2), this.lines(i,4), nPtsPrLine);
				for j=1:nPtsPrLine
					res = this.point(u(j), v(j));
					x(j,i) = res(1);
					y(j,i) = res(2);
				end
			end
			H = plot(x,y, 'k-');

			if(nargin > 1 && strcmp(varargin{1}, 'enumeration'))
				hold on;
				for i=1:size(this.elements, 1),
					x = this.point(sum(this.elements(i, [1,3]))/2, sum(this.elements(i,[2,4]))/2);
					text(x(1), x(2), num2str(i));
				end
				hold off;
			end
		end

		function H = surf(this, u)
			nviz = 6; % evaluation points per element
			xg = linspace(-1,1,nviz);
			u = u(:)'; % make u a row vector

			bezierKnot1 = [ones(1, this.p(1)+1)*-1, ones(1, this.p(1)+1)];
			bezierKnot2 = [ones(1, this.p(2)+1)*-1, ones(1, this.p(2)+1)];
			[bezNu, bezNu_diff] = getBSplineBasisAndDerivative(this.p(1), xg, bezierKnot1); 
			[bezNv, bezNv_diff] = getBSplineBasisAndDerivative(this.p(2), xg, bezierKnot2); 
			for iel=1:length(this.elements)
				umin = this.elements(iel,1);
				vmin = this.elements(iel,2);
				umax = this.elements(iel,3);
				vmax = this.elements(iel,4);
				ind  = this.support{iel}; % indices to nonzero basis functions
				C = this.getBezierExtraction(iel);
				X = zeros(nviz);
				Y = zeros(nviz);
				U = zeros(nviz);
				% for all gauss points
				for i=1:nviz
					for j=1:nviz
						% compute all basis functions
						N = bezNu(:,i) * bezNv(:,j)';
						N = N(:); % and make results colum vector

						% evaluates physical mapping and solution
						x = this.cp(:,ind) * C * N;
						X(i,j) = x(1);
						Y(i,j) = x(2);
						U(i,j) = u(ind) * C * N;
					end
				end
				H = surf(X,Y,U, 'EdgeColor', 'none'); hold on;
				plot3(X(1,:),   Y(1,:),   U(1,:),   'k-');
				plot3(X(end,:), Y(end,:), U(end,:), 'k-');
				plot3(X(:,1),   Y(:,1),   U(:,1),   'k-');
				plot3(X(:,end), Y(:,end), U(:,end), 'k-');
			end
		end
	end

	methods (Access = private, Hidden = true)
		function updatePrimitives(this)
			[this.knots, this.cp, this.w, ...
			 this.lines, this.elements,   ...
			 this.support, this.p] = lrsplinesurface_interface('get_primitives', this.objectHandle);
		end
	end
end
