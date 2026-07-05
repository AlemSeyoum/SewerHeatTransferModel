function [Tw_in_before, Tw_out, Tw_mesh_plot] = init_temperature_state_opportunity( ...
    Tw_in_before, Tw_out, Tw_mesh_plot, ...
    topoOrder, isSource, usLinkIndex, SubcmPipeIndex, scCounts, ...
    Tw0, Tfoul, Ttrade, qfoul, qtrade, ...
    Qds, Qus, Vus, Dus, ...
    Shapes, R, L, Mesh, ...
    kp, t, ksds, fc, Ta, SoilTemp, ...
    rho, cp, ...
    jT, plotTimeIndex)

    %#ok<INUSD>  % some inputs kept for interface compatibility

    N = numel(R);

    % -----------------------------------------------------------------
    % Robust initial network temperature
    % Use mean finite source temperature at jT; fall back to foul temp
    % -----------------------------------------------------------------
    Tinit = mean(Tw0(jT, isfinite(Tw0(jT,:))), 'omitnan');
    if ~isfinite(Tinit)
        Tinit = mean(Tfoul(jT, :), 'omitnan');
    end
    if ~isfinite(Tinit)
        Tinit = 10.5;   % final fallback
    end

    % Start from a fully defined temperature field
    Tw_out_prev = Tinit * ones(1, N);

    % Where source temperatures are available, use them
    srcFinite = isfinite(Tw0(jT,:));
    Tw_out_prev(srcFinite) = Tw0(jT, srcFinite);

    % -----------------------------------------------------------------
    % Topological pass to define Tin and Tout at the first timestep
    % IMPORTANT: initialization is adiabatic (no heat loss at t=1)
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

                % Guard against bad indices
                if ~isfinite(upPipe) || upPipe < 1 || upPipe > N
                    continue
                end

                qk = Qds(jT, upPipe);
                tk = Tw_out_prev(upPipe);

                if ~isfinite(qk) || qk <= 0
                    continue
                end
                if ~isfinite(tk)
                    continue
                end

                Q_up  = Q_up  + qk;
                TQ_up = TQ_up + qk * tk;
            end

            % Local subcatchment foul + trade
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
                % Safe fallback for non-source pipes
                Tin = Tw_out_prev(I);
                if ~isfinite(Tin)
                    Tin = Tinit;
                end
            end
        end

        % Store inlet temperature
        Tw_in_before(jT, I) = Tin;

        % -------------------------------------------------------------
        % Initialization is adiabatic:
        % set outlet equal to inlet for ALL links at t=1
        % This avoids artificial spikes and NaN propagation.
        % -------------------------------------------------------------
        Tw_out(jT, I) = Tin;
        Tw_out_prev(I) = Tin;

        % Mesh profile is uniform at initialization
        Tw_prof = Tin * ones(1, Mesh+1);

        if jT == plotTimeIndex
            Tw_mesh_plot(I,:) = Tw_prof;
        end
    end

    % Final safety cleanup
    badIn  = ~isfinite(Tw_in_before(jT,:));
    badOut = ~isfinite(Tw_out(jT,:));

    Tw_in_before(jT, badIn) = Tinit;
    Tw_out(jT, badOut)      = Tinit;

    if jT == plotTimeIndex
        badMesh = ~isfinite(Tw_mesh_plot);
        Tw_mesh_plot(badMesh) = Tinit;
    end
end