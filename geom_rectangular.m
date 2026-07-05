function [b, Larc] = geom_rectangular(W, H, Dw)
%GEOM_RECTANGULAR  Wetted geometry for rectangular conduit
%   W  = width [m]
%   H  = height [m]
%   Dw = water depth [m]

Dw = max(Dw, 1e-9);
Dw = min(Dw, H);

b = W;

if Dw < H
    Larc = W + 2*Dw;
else
    Larc = W + 2*H;
end
end
