function [Tw_in_before, Tw_in_after, Tw_out] = init_temperature_state( ...
    Tw_in_before, Tw_in_after, Tw_out, ...
    topoOrder, isSource, usLinkIndex, SubcmPipeIndex, scCounts, ...
    Tw0, Tfoul, Ttrade, qfoul, qtrade, ...
    Qds, Qus, Vus, Dus, ...
    Shapes, R, L, Mesh, ...
    kp, t, ksds, fc, Ta, SoilTemp, ...
    rho, cp, ...
    HexPipes, HexPowerReq, TminHex, ...
    jT)

    %#ok<INUSD>
    % Some inputs are kept for interface compatibility with the main code.
    % Initialization is intentionally simple:
    %   - no extraction
    %   - no infiltration
    %   - no heat loss along links
    %   - adiabatic start with stable mixed temperatures

    N = numel(R);

    % -----------------------------------------------------------------
    % Robust initial background temperature
    % -----------------------------------------------------------------
    Tinit = mean(Tw0(jT, isfinite(Tw0(jT,:))), 'omitnan');
    if ~isfinite(Tinit)
        Tinit = mean(Tfoul(jT, :), 'omitnan');
    end
    if ~isfinite(Tinit)
        Tinit = 10.5;   % final fallback
    end

    % -----------------------------------------------------------------
    % Start from a fully defined temperature field
    % -----------------------------------------------------------------
    Tw_prev = Tinit * ones(1, N);

    % Where source temperatures exist, use them
    srcFinite = isfinite(Tw0(jT,:));
    Tw_prev(srcFinite) = Tw0(jT, srcFinite);

    % -----------------------------------------------------------------
    % Topological pass: define Tin at t = 1
    % -----------------------------------------------------------------
    for idx = 1:numel(topoOrder)
        I = topoOrder(idx);

        if isSource(I)
            Tin = Tw0(jT, I);
            if ~isfinite(Tin)
                Tin = Tinit;
            end
        else
            ups = usLinkIndex{I};

            Q_up  = 0;
            TQ_up = 0;

            for k = 1:numel(ups)
                upPipe = ups(k);

                % Guard against invalid upstream indices
                if ~isfinite(upPipe) || upPipe < 1 || upPipe > N
                    continue
                end

                qk = Qds(jT, upPipe);
                tk = Tw_prev(upPipe);

                if ~isfinite(qk) || qk <= 0
                    continue
                end
                if ~isfinite(tk)
                    continue
                end

                Q_up  = Q_up  + qk;
                TQ_up = TQ_up + qk * tk;
            end

            % Local foul + trade inflow
            sc = SubcmPipeIndex(I);
            Q_loc  = 0;
            TQ_loc = 0;

            if sc > 0 && sc <= size(qfoul,2)
                share = 1;
                if ~isempty(scCounts) && sc <= numel(scCounts) && scCounts(sc) > 0
                    share = scCounts(sc);
                end

                qf = qfoul(jT, sc) / share;
                qt = qtrade(jT, sc) / share;

                if isfinite(qf) && isfinite(qt) && qf >= 0 && qt >= 0
                    Q_loc  = qf + qt;
                    TQ_loc = Tfoul(jT, sc) * qf + Ttrade(jT, sc) * qt;
                end
            end

            Qtot = Q_up + Q_loc;

            if Qtot > 0
                Tin = (TQ_up + TQ_loc) / Qtot;
            else
                % Fallback to previous initialized field
                Tin = Tw_prev(I);
                if ~isfinite(Tin)
                    Tin = Tinit;
                end
            end
        end

        % -------------------------------------------------------------
        % Initialization is adiabatic and has no extraction:
        % Tin_before = Tin_after = Tout at t = 1
        % -------------------------------------------------------------
        Tw_in_before(jT, I) = Tin;
        Tw_in_after(jT, I)  = Tin;
        Tw_out(jT, I)       = Tin;

        % Update field for downstream links in same topological pass
        Tw_prev(I) = Tin;
    end

    % -----------------------------------------------------------------
    % Final safety cleanup
    % -----------------------------------------------------------------
    badBefore = ~isfinite(Tw_in_before(jT,:));
    badAfter  = ~isfinite(Tw_in_after(jT,:));
    badOut    = ~isfinite(Tw_out(jT,:));

    Tw_in_before(jT, badBefore) = Tinit;
    Tw_in_after(jT, badAfter)   = Tinit;
    Tw_out(jT, badOut)          = Tinit;
end