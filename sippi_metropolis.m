function [options,data,prior,forward,m_current]=sippi_metropolis(data,prior,forward,options)
% sippi_metropolis Extended Metropolis sampling in SIPPI
%
% Metropolis sampling.
%   See e.g.
%     Hansen, T. M., Cordua, K. S., and Mosegaard, K., 2012.
%     Inverse problems with non-trivial priors - Efficient solution through Sequential Gibbs Sampling.
%     Computational Geosciences. doi:10.1007/s10596-011-9271-1.
%
%     Sambridge, M., 2013 - A Parallel Tempering algorithm for
%     probabilistic sampling and multi-modal optimization.
%
% Call :
%    [options,data,prior,forward,m_current]=sippi_metropolis(data,prior,forward,options)
% Input :
%    data : sippi data structure
%    prior : sippi prior structure
%    forward : sippi forward structure
%
% options :
%
%    options.mcmc.nite=30000;   % [1] : Number if iterations
%    options.mcmc.i_sample=100; % : Number of iterations between saving model to disk
%    options.mcmc.i_plot=50;  % [1]: Number of iterations between updating plots
%    options.mcmc.i_save_workspace=10000;  % [1]: Number of iterations between
%                                            saving the complete workspace
%    options.mcmc.i_sample=100; % : Number of iterations between saving model to disk
%
%    options.mcmc.m_init : Manually chosen starting model
%    options.mcmc.m_ref  : Reference known target model
%
%    options_mcmc.accept_only_improvements [0] : Optimization
%
%    options.txt [string] : string to be used as part of all output file names
%
%    %% PERTURBATION STRATEGY
%    % Perturb all model parameter all the time
%    options.mcmc.pert_strategy.perturb_all=1; % Perturb all priors in each
%                                              % iteration. def =[0]
%
%    % Perturb one a prior type at a time, according to some frequency
%    options.mcmc.pert_strategy.i_pert = [1,3]; % only perturb prior 1 and 3
%    options.mcmc.pert_strategy.i_pert = [2 8]; % perturb prior 3 80% of
%                                               % the time and prior 1 20%
%                                               % of the time
%    % the default pertubation strategt is to select one prior model to 
%    % perturb at tandom for each iteration 
%
%
%    %% TEMPERING
%    options.mcmc.n_chains=1; % set number of chains (def=1)
%    options.mcmc.T=1;      % set temperature of chains [1:n_chains]
%    options.mcmc.chain_frequency_jump=0.1; % probability allowing a jump
%                                           %  between two chains
%    %% ANNEALING (TEMPERATURE AS A FUNCTION OF ITERATION NUMBER)
%    options.mcmc.anneal.i_begin=1; % default, iteration number when annealing begins
%    options.mcmc.anneal.i_end=100000; %  iteration number when annealing stops
%    options.mcmc.anneal.T_begin=5; % Start temperature for annealing 
%    options.mcmc.anneal.T_end=1; % End temperature for annealing 
% 
%    %% VERBOSITY
%    The amount of text info displayed at the prompt, can be controlled by
%    setenv('SIPPI_VERBOSE_LEVEL','2') % all: information on chain swapping
%    setenv('SIPPI_VERBOSE_LEVEL','1') % information about seq-gibbs step update
%    setenv('SIPPI_VERBOSE_LEVEL','0'); % [def] frequent update 
%    setenv('SIPPI_VERBOSE_LEVEL','-1'); % rare update om finish time
%    setenv('SIPPI_VERBOSE_LEVEL','-2'); % indication of stop and start
%    setenv('SIPPI_VERBOSE_LEVEL','-3'); % none
%
% See also sippi_rejection
%
%

options.null='';
if ~isfield(options,'txt');options.txt='';end
if ~isempty(options.txt)
    options.txt=sprintf('%s_sippi_metropolis_%s',datestr(now,'YYYYmmdd_HHMM'),options.txt);
else
    options.txt=sprintf('%s_sippi_metropolis',datestr(now,'YYYYmmdd_HHMM'));
end
try
    options.txt=sprintf('%s_%s',options.txt,forward.type);
catch
    % No forward.type
end

start_dir=pwd;
%% MAKE OUTPUT DIR
try;
    mkdir(options.txt);
    cd(options.txt);
    addpath(['..',filesep])
    
    for im=1:length(prior);
        if isstr(prior{im}.ti)
            try
                if isunix
                    system(sprintf('cp ..%s%s . ',filesep,prior{im}.ti));
                else
                    system(sprintf('copy ..%s%s ',filesep,prior{im}.ti));
                end
            end
        end
    end
end




nm=length(prior); % numer prior types

%% INITIALIZE MCMC OPTIONS
options=sippi_mcmc_init(options,prior);
if ~isfield(options,'mcmc'); options.mcmc.null='';end
if ~isfield(options.mcmc,'n_chains'); options.mcmc.n_chains=1;end

mcmc=options.mcmc;


%% INITIALIZE prior
prior=sippi_prior_init(prior);

%% INITIALIZE data
for id=1:length(data)
    if ~isfield(data{id},'i_use');
        data{id}.i_use=find(ones(size(data{id}.d_obs)));
    end
    %data{id}.N=prod(size(data{id}.d_obs));
    data{id}.N=length(data{id}.i_use);
end

%% INITIALIZE CHAINS
NC=options.mcmc.n_chains;
for ic=1:NC
    C{ic}.prior=prior;
    C{ic}.data=data;
    C{ic}.forward=forward;
end

% set Temperature
if ~isfield(mcmc,'T');
    if ~isfield(mcmc,'T_min');mcmc.T_min=1;end
    if ~isfield(mcmc,'T_max');mcmc.T_max=NC;end
    
    if NC==1;
        mcmc.T=mcmc.T_min;
    else
        mcmc.T=linspace(mcmc.T_min,mcmc.T_max,NC);
    end
end

for ic=1:NC
    C{ic}.T=mcmc.T(ic);
end

if ~isfield(mcmc,'chain_frequency_jump');
    mcmc.chain_frequency_jump=0.1;
end

%% CHECK FOR ANNEALING
if isfield(mcmc,'anneal');
    do_anneal=1;
else
    do_anneal=0;
    T_fac=1;
end

%% STARTING  MODEL
for ic=1:NC
    if isfield(mcmc,'m_init');
        C{ic}.m_current=mcmc.m_init;
        sippi_verbose(sprintf('Using supplied model as starting model',mfilename));
    else
        [C{ic}.m_current,C{ic}.prior] = sippi_prior(C{ic}.prior);
    end
end


%% INITIAL LIKELIHOODS
for ic=1:NC
    [C{ic}.d_current,C{ic}.forward,C{ic}.prior,C{ic}.data]=sippi_forward(C{ic}.m_current,C{ic}.forward,C{ic}.prior,C{ic}.data);
    
    C{ic}.data_current=C{ic}.data;
    [C{ic}.logL_current,C{ic}.L_current]=sippi_likelihood(C{ic}.d_current,C{ic}.data_current);
    
    C{ic}.prior_current=C{ic}.prior;
    
end

%% COMPUTE TIME PER ITERATION
% COMPUTE THE TIME OF ONE CALL TO SIPPI_PRIOR
for ic=1:NC
    [m_tmp,prior_tmp] = sippi_prior(C{ic}.prior); % make sure prior is set
    tic
    [m_tmp,prior_tmp] = sippi_prior(prior_tmp);
    t_prior(ic)=toc;
    
    % COMPUTE THE TIME OF ONE CALL TO SIPPI_FORWARD
    [d_init,forward,prior,data]=sippi_forward(m_tmp,C{ic}.forward,prior_tmp,C{ic}.data);
    tic,
    d_current=d_init;
    t_data(ic)=toc;
    clear m_tmp prior_tmp d_init;
end
t_per_ite=sum(t_data)+sum(t_prior);

% compute the number of iterations between text updates on the screen based
% on the of one forward evaluation (t_data), if not alloready set
if isfield(options,'i_update_txt');
    i_update_txt=options.i_update_txt;
else
    vlevel=sippi_verbose;
    if vlevel<0, t_up=50; else, t_up=5; end
    
    i_update_txt=max([1 ceil(t_up./(t_per_ite))]);
end

%% PRE ALLOCATE ARRAY FOR MCMC OUTPUT
if NC>1
    mcmc.i_swap=ones(2,mcmc.nite).*NaN;
    n_swap=0;
end

for ic=1:NC
    if length(data)>1
        C{ic}.mcmc.logL_all=zeros(length(C{ic}.data),mcmc.nite);
    end
    C{ic}.mcmc.logL=zeros(1,mcmc.nite);
    C{ic}.mcmc.acc=zeros(nm,mcmc.nite);
    C{ic}.mcmc.perturb=zeros(nm,mcmc.nite);
    C{ic}.mcmc.step=zeros(nm,mcmc.nite);
    C{ic}.mcmc.time=zeros(1,mcmc.nite);
    
    if mcmc.store_all==1
        %    C{ic}.logL_all = zeros(1,mcmc.nite);
        C{ic}.m_cur_all = zeros(nm,mcmc.nite);
    end
    
    C{ic}.iacc=0;
    C{ic}.isample=0;
    
end


%% INITIALIZE ASC FILE
for ic=1:NC
    for im=1:nm
        C{ic}.filename_asc{im}=sprintf('%s_m%d_C%d%s',options.txt,im,ic,'.asc');
        C{ic}.fid=fopen(C{ic}.filename_asc{im},'w');
        fclose(C{ic}.fid);
    end
end
filename_mat=[options.txt,'.mat'];

%% SET DFAULT PLOTTING SETTINGS
options=sippi_plot_defaults(options);

%% START THE METROPOLIS ALGORITHM
sippi_verbose(sprintf('%s : Starting extended Metropolis sampler in %s',mfilename,options.txt),-2);
if NC>1
    T_str=sprintf('%3.1f ',mcmc.T);
    sippi_verbose(sprintf('%s : Using %d chains at temperatures: %s',mfilename,NC,T_str),-2);
end
mcmc.t_start=now;
for i=1:mcmc.nite;
    mcmc.i=i;
    mcmc.time(i)=now;
    
    
    for ic=1:NC
        
        %% set seed / necessary?
        for im=1:length(C{ic}.prior_current)
            C{ic}.prior_current{im}.seed=i;
        end
        
        %% SELECT IF STEP LENGTH HAS TO BE UPDATED
        for im=1:length(C{ic}.prior_current)
            if (( (mcmc.i./C{ic}.prior_current{im}.seq_gibbs.i_update_step)==round((mcmc.i./C{ic}.prior_current{im}.seq_gibbs.i_update_step)))&(mcmc.i<C{ic}.prior_current{im}.seq_gibbs.i_update_step_max))
                % UPDATE STEP LENGTH
                C{ic}.prior_current=sippi_prior_set_steplength(C{ic}.prior_current,C{ic}.mcmc,im);
            end
            C{ic}.mcmc.step(im,i)=C{ic}.prior_current{im}.seq_gibbs.step(1);
        end
        
        %% Sample prior
        % SELECT WHICH MODEL PARAMETERS TO PERTURB
        
        for im=1:length(C{ic}.prior_current);
            C{ic}.prior_current{im}.perturb=0;
        end
        
        % PERTURBATION STRATEGY
        if mcmc.pert_strategy.perturb_all==1,
            im_perturb=1:1:length(C{ic}.prior_current);
        else
            % perturb one parameter according to frequency distribution
            i_pert=mcmc.pert_strategy.i_pert;
            pert_freq=cumsum(mcmc.pert_strategy.i_pert_freq);
            pert_freq=pert_freq./max(pert_freq);
            im_perturb=i_pert(min(find(rand(1)<pert_freq)));
        end
        for k=1:length(im_perturb);
            C{ic}.prior_current{im_perturb(k)}.perturb=1;
            C{ic}.mcmc.perturb(im_perturb(k),i)=1;
        end
        
        % SAMPLE PRIOR
        [C{ic}.m_propose,C{ic}.prior_propose] = sippi_prior(C{ic}.prior_current,C{ic}.m_current);
        
        %% FORWARD PROBLEM
        [C{ic}.d,C{ic}.forward,C{ic}.prior_propose,C{ic}.data]=sippi_forward(C{ic}.m_propose,C{ic}.forward,C{ic}.prior_propose,C{ic}.data);
        
        %% LIKELIHOOD
        [C{ic}.logL_propose,C{ic}.L_propose,C{ic}.data]=sippi_likelihood(C{ic}.d,C{ic}.data);
        
        %%  MOVE?
        % Accept probability
        
        
        % set temperature
        if do_anneal==1;
            [T_fac,mcmc]=sippi_anneal_temperature(i,mcmc,C{ic}.prior_current);
        end
        T=T_fac.*C{ic}.T;
        
        C{ic}.Pacc = exp((1./T).*(C{ic}.logL_propose-C{ic}.logL_current));
        
        if (mcmc.accept_only_improvements==1)
            % Optimization only?
            if C{ic}.logL_propose>C{ic}.logL_current
                C{ic}.Pacc=1;
            else
                C{ic}.Pacc=0;
            end
        end
        % Optionally accept all proposed models
        if (mcmc.accept_all==1), C{ic}.Pacc=1; end
        
        % Aceept move
        C{ic}.forward.last_proposed_model_accept=0; %
        if C{ic}.Pacc>rand(1)
            % ACCEPT MODEL
            C{ic}.forward.last_proposed_model_accept=1;
            
            % move to current model
            C{ic}.prior_current=C{ic}.prior_propose; % NEEDED FOR GAUSSIAN TYPE PRIOR
            C{ic}.m_current=C{ic}.m_propose;
            C{ic}.d_current=C{ic}.d;
            C{ic}.logL_current=C{ic}.logL_propose;
            C{ic}.L_current=C{ic}.L_propose;
            C{ic}.iacc=C{ic}.iacc+1;
            %C{ic}.mcmc.logL(C{ic}.iacc)=C{ic}.logL_current;
            C{ic}.mcmc.acc(im_perturb,mcmc.i)=1;
            
        else
            % REJECT MOVE MODEL
        end
        C{ic}.mcmc.logL(mcmc.i)=C{ic}.logL_current;
        
        
        if mcmc.store_all==1
            %C{ic}.logL_all(i)=C{ic}.logL_current;
            for im=1:length(prior);
                C{ic}.m_cur_all(im,i) = C{ic}.m_current{im}(1);
            end
        end
        
        % SAVE CURRENT MODEL
        if ((mcmc.i/mcmc.i_sample)==round( mcmc.i/mcmc.i_sample ))
            C{ic}.isample=C{ic}.isample+1;
            %mcmc.i_sample_logL(isample)=logL_current;
            for im=1:nm
                fid=fopen(C{ic}.filename_asc{im},'a+');
                fprintf(C{ic}.fid,' %10.7g ',[C{ic}.m_current{im}(:)]);
                fprintf(C{ic}.fid,'\n');
                fclose(C{ic}.fid);
            end
        end
        
    end % END MC CHAIN LOOP
    
    %% TEMPERING
    if NC>1
        if rand(1)<mcmc.chain_frequency_jump; %frequency of swap tests
            % IF TEMPERING
            ic_i=ceil(NC*rand(1));
            j_arr=setxor(1:NC,ic_i);
            ic_j=j_arr(ceil((NC-1)*rand(1)));
            
            Pi=exp(C{ic_j}.logL_current-C{ic_i}.logL_current).^(1./C{ic_i}.T);
            Pj=exp(C{ic_i}.logL_current-C{ic_j}.logL_current).^(1./C{ic_j}.T);
            
            Pacc=Pi*Pj;
            if rand(1)<Pacc
                % accept swap
                n_swap=n_swap+1;
                
                mcmc.i_swap(1,n_swap)=ic_i;
                mcmc.i_swap(2,n_swap)=ic_j;
                
                % perform the swap
                C_i=C{ic_i};
                
                C{ic_i}.m_current=C{ic_j}.m_current;
                C{ic_i}.prior_current=C{ic_j}.prior_current;
                C{ic_i}.data=C{ic_j}.data;
                C{ic_i}.logL_current=C{ic_j}.logL_current;
                C{ic_i}.m_current=C{ic_j}.m_current;
                
                C{ic_j}.m_current=C_i.m_current;
                C{ic_j}.prior_current=C_i.prior_current;
                C{ic_j}.data=C_i.data;
                C{ic_j}.logL_current=C_i.logL_current;
                C{ic_j}.m_current=C_i.m_current;
                
                % Keep step length constant within chains
                for k=1:NC;for im=1:length(C{k}.prior_current);
                        C{k}.prior_current{im}.seq_gibbs.step=C{k}.mcmc.step(im,i);
                end;end
                sippi_verbose(sprintf('%s: at i=%05d SWAP chains [%d<->%d]',mfilename,i,ic_i,ic_j),2);
            end
        end
    end
    
    %% SAVE WORKSPACE
    if ((mcmc.i/(mcmc.i_save_workspace))==round( mcmc.i/(mcmc.i_save_workspace) ))
        try
            save(filename_mat,'-v7.3')
        catch
            disp(sprintf('%s : failed to save data to %s',mfilename,filename_mat))
        end
    end
    
    %% DISPLAY PROGRES AND TIME TO FINISH
    if ((i/i_update_txt)==round(i/i_update_txt))
        [t_end_txt,t_left_seconds]=time_loop_end(mcmc.t_start,i,mcmc.nite);
        %ic=1;
        vlevel=sippi_verbose;
        if vlevel>0, NC_end=NC; else NC_end=1; end
        for ic=1:NC_end
            sippi_verbose(sprintf('%06d/%06d (%10s): C%02d acc %5g %5g  T=%5.2f',mcmc.i,mcmc.nite,t_end_txt,ic,C{ic}.logL_current,C{ic}.logL_propose,C{ic}.T*T_fac),-1);
        end
    end
    
    %% PLOT CURRENT MODEL AND STATUS
    if ((mcmc.i/mcmc.i_plot)==round( mcmc.i/mcmc.i_plot ))
        try
            C{1}.mcmc.i=mcmc.i;            
            sippi_plot_current_model(C{1}.mcmc,C{1}.data,C{1}.d_current,C{1}.m_current,C{1}.prior_current);
        catch
            sippi_verbose(sprintf('%s : Could not plot current model info',mfilename),-10);
        end
        %%
        if NC>1
            figure_focus(35);clf;
            ylim=[min(C{1}.mcmc.logL(ceil(i*.1):i)),max(C{1}.mcmc.logL(ceil(i*.1):i))];
            for ic=1:NC;
                L{ic}=sprintf('T=%3.1f',C{ic}.T);
                
                lmin=min(C{ic}.mcmc.logL(ceil(i*.1):i));
                lmax=max(C{ic}.mcmc.logL(ceil(i*.1):i));
                if lmin<ylim(1),ylim(1)=lmin;end
                if lmax>ylim(2),ylim(2)=lmax;end
                
                plot(1:i,C{ic}.mcmc.logL(1:i),'-');
                hold on
            end
            hold off
            
            set(gca,'ylim',ylim)
            legend(L,'location','northeastoutside')
            xlabel('Iteration number')
            ylabel('log(L)')
            grid on
            
        end
        drawnow
    end
end

if NC>1
    mcmc.i_swap = mcmc.i_swap(:,1:n_swap);
end

mcmc.t_end=now;
mcmc.time_elapsed_in_seconds=3600*24*(mcmc.t_end-mcmc.t_start);

m_current=C{1}.m_current;
mcmc.m_current=m_current;

options.C=C; % PERHAPS TOO MEMORY INTENSIVE
options.mcmc=mcmc; % PERHAPS TOO MEMORY INTENSIVE
save(filename_mat,'-v7.3')
sippi_verbose(sprintf('%s : DONE McMC in %5.2f hours, %s',mfilename,mcmc.time_elapsed_in_seconds/3600,options.txt),-2);

%%
cd(start_dir);

