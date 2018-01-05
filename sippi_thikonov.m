% sippi_least_squares Least squares type inversion for SIPPI
%
% Call :
%    [options,data,prior,forward,m_reals,m_est,Cm_est]=sippi_least_squares(data,prior,forward,options);
%
%   options.lsq.type    : LSQ type to use ('lsq' (classical linear leqast squares) is the default)
%   options.lsq.n_reals : Number of realizations to generate
%   options.lsq.plot : [0/1] show figures or not def->0.
%   options.lsq.save_data : [0/1] save realizations to output folder. def->1.
%
%
% TMH/01/2017
%
% See also sippi_rejection, sippi_metropolis
%



%              'error_sim', simulation through error simulation
%              'visim', simulation through SGSIM of DSSIM
%
function [m_est,Cm_est,m_reals,options,data,prior,forward]=sippi_thikonov(data,prior,forward,options);

id=1;
im=1;

m_reals=[];
m_est=[];
Cm_est=[];
options.lsq.null=''; % make sutre options.lsq exists


% save data?
if ~isfield(options.lsq,'save_data')
    options.lsq.save_data=1;
end


% plot?
if ~isfield(options.lsq,'plot')
    options.lsq.plot=0;
end


%% CHOOSE NAME
if ~isfield(options,'txt')
    options.txt=mfilename;
end

try
    options.txt=sprintf('%s_%s_%s',datestr(now,'YYYYmmdd_HHMM'),options.txt,options.lsq.type);
catch
    options.txt=sprintf('%s_%s',datestr(now,'YYYYmmdd_HHMM'),options.txt);
end
sippi_verbose(sprintf('%s: output folder: %s ',mfilename,options.txt),1)


%% MODEL COVARINCE
if ~isfield(options.lsq,'Cm');
    prior=sippi_prior_init(prior);
    if isfield(prior{im},'Cmat');
        options.lsq.Cm=prior{im}.Cmat;
    else
        prior=sippi_prior_init(prior);
        options.lsq.Cm=precal_cov([prior{im}.xx(:) prior{im}.yy(:) prior{im}.zz(:)],[prior{im}.xx(:) prior{im}.yy(:) prior{im}.zz(:)],prior{im}.Va);
    end
end
if ~isfield(options.lsq,'Cm');
    sippi_verbose(sprintf('%s: Could not model covariance Cm. Please use a Gaussian prior or set prior{%d}.Cmat',mfilename,id),0)
else
    sippi_verbose(sprintf('%s: Model covariance, Cm, set in options.lsq.Cm',mfilename),1)
end

%% DATA COVARINCE
if isfield(data{id},'CD');
    options.lsq.Cd=data{id}.CD;
else
    % solve the forwrad problem and make use of data{1}.CD if it exists
    m=sippi_prior(prior);
    [d,forward,prior,data]=sippi_forward(m,forward,prior,data);
    [logL,L,data]=sippi_likelihood(d,data,id);
    try
        options.lsq.Cd=data{id}.CD;
    end
end

%if ~isfield(options.lsq,'Cd');
% No correlated noise is set...
if isfield(data{id},'d_std');
    if length(data{id}.d_std)==1;
        options.lsq.Cd=eye(length(data{id}.d_obs)).*data{id}.d_std.^2;
    else
        options.lsq.Cd=diag(data{1}.d_std.^2);
    end
end
if isfield(data{id},'d_var');
    if length(data{id}.d_var)==1;
        options.lsq.Cd=eye(length(data{id}.d_obs)).*data{id}.d_var;
    else
        options.lsq.Cd=diag(data{1}.d_var);
    end
end
%end


if ~isfield(options.lsq,'Cd');
    sippi_verbose(sprintf('%s: Could not data covariance Cd. Please use a Gaussian noise model in data{%d}',mfilename,id),0)
else
    sippi_verbose(sprintf('%s: Data covariance, Cd, set in options.lsq.Cd',mfilename),1)
end


%% CHECK FOR FORWARD OPERATOR
if ~isfield(forward,'G');
    % assume the forward operator is output in forward.G if sippi_forward
    % is run
    try
        m=sippi_prior(prior);
        if isfield(forward,'forward_function');
            [d,forward,prior,data]=feval(forward.forward_function,m,forward,prior,data,id,im);
        else
            [d,forward,prior,data]=sippi_forward(m,forward,prior,data,id,im);
        end
    end
    if ~isfield(forward,'G');
        sippi_verbose(sprintf('%s : No forward operator G found in forward',mfilename),0)
    end
end
try
    options.lsq.G=forward.G;
end
if ~isfield(options.lsq,'G');
    sippi_verbose(sprintf('%s: linear forward operator G is not set. Please set in in forward.G',mfilename,id),0)
else
    sippi_verbose(sprintf('%s: linear forward operator G set in options.lsq.G',mfilename),1)
end


%% M
if ~isfield(prior{im},'m0');
    prior{im}.m0=0;
end
if length(prior{im}.m0)==1;
    nm=size(options.lsq.Cm,1);
    options.lsq.m0=ones(nm,1).*prior{im}.m0;
else
    options.lsq.m0=prior{im}.m0(:);
end
sippi_verbose(sprintf('%s: setting options.lsq.m0=prior{%d}.m0',mfilename,im),1)

%% D
if ~isfield(data{id},'d0');
    options.lsq.d0=data{id}.d_obs.*0;
    sippi_verbose(sprintf('%s: setting options.lsq.d0=0;',mfilename),1)
end
options.lsq.d_obs=data{id}.d_obs;
sippi_verbose(sprintf('%s: setting options.lsq.d_obs=data{%d}.d_obs',mfilename,id),1)


%% THIKONOV
x = prior{1}.x;nx=length(x);
y = prior{1}.y;ny=length(y);

I = eye(size(options.lsq.Cm,1));

e_N = 21;
e_min = -3;
e_max = 3;
e_array = logspace(e_min,e_max, e_N);
for i=1:length(e_array);
    e = e_array(i);
    
    % classical
    %m_est = inv(options.lsq.G'*options.lsq.G + e.*I)*options.lsq.G'*(options.lsq.d_obs(:));
    % general, m0
    %m_est = options.lsq.m0 + inv(options.lsq.G'*options.lsq.G + e^2.*I)*options.lsq.G'*(options.lsq.d_obs(:)-options.lsq.G*options.lsq.m0);
    
    % general, m0, Cm
    %m_est = options.lsq.m0 + inv(options.lsq.G'*options.lsq.G + e^2.*I)*options.lsq.G'*(options.lsq.d_obs(:)-options.lsq.G*options.lsq.m0);
    
    % Generalized w. PROPER weight matrices
    m_est = options.lsq.m0 + inv(options.lsq.G'*options.lsq.Cd*options.lsq.G + e^2.*inv(options.lsq.Cm))*options.lsq.G'*options.lsq.Cd*(options.lsq.d_obs(:)-options.lsq.G*options.lsq.m0);
    %m_est = options.lsq.m0 + inv(options.lsq.G'*options.lsq.Cd*options.lsq.G + e^2.*I)*options.lsq.G'*options.lsq.Cd*(options.lsq.d_obs(:)-options.lsq.G*options.lsq.m0);
    
    
    m_norm(i) = norm(m_est - options.lsq.m0);
    d_norm(i) = norm(options.lsq.d_obs - options.lsq.G*m_est);
    
    
    figure(1);
    subplot(2,ceil(e_N/2),i);
    imagesc(x,y,reshape(m_est,ny,nx));
    try;caxis(prior{1}.cax);end
    axis image;
    colorbar
    drawnow;
    
    
     
    
    
end

%%
figure(3);
plot(m_norm,d_norm,'-*')
xlabel('||m-m0||')
ylabel('||d-Gm||')
    
figure(4);
loglog(m_norm,d_norm,'-*')
xlabel('||m-m0||')
ylabel('||d-Gm||')
    


return



%% SCALE M_EST
x=prior{im}.x;y=prior{im}.y;z=prior{im}.z;
if prior{im}.dim(3)>1
    % 3D
    m_est{im}=reshape(m_est{im},length(y),length(x),length(z));
    
elseif prior{im}.dim(2)>1
    % 2D
    m_est{im}=reshape(m_est{im},length(y),length(x));
    Cm_est_diag = reshape(diag(Cm_est{im}),length(y),length(x));    
else
    % 1D
    Cm_est_diag = diag(Cm_est{im});
end


%% EXPORT REALIZATIONS TO DISK
if (options.lsq.save_data==1)
    
    options.cwd=pwd;
    try;
        mkdir(options.txt);
    end
    % REALS
    filename_asc{im}=sprintf('%s%s%s_m%d%s',options.txt,filesep,options.txt,im,'.asc');
    fid=fopen(filename_asc{im},'w');
    for i=1:options.lsq.n_reals
        fprintf(fid,' %10.7g ',m_reals(:,i));
        fprintf(fid,'\n');
    end
    fclose(fid);
    
    
    filename_m_est{im}=sprintf('%s%s%s_m%d_mest%s',options.txt,filesep,options.txt,im,'.asc');
    sippi_verbose(sprintf('%s: Writing m_est to %s',mfilename,filename_m_est{im}),1);
    %fid=fopen(filename_m_est{im},'w');fprintf(fid,' %10.7g ',m_est(:));fclose(fid);
    
    filename_Cm_est{im}=sprintf('%s%s%s_m%d_Cmest%s',options.txt,filesep,options.txt,im,'.asc');
    sippi_verbose(sprintf('%s: Writing Cm_est to %s',mfilename,filename_Cm_est{im}),1);
    %fid=fopen(filename_Cm_est{im},'w');fprintf(fid,' %10.7g ',Cm_est(:));fclose(fid);
    
    filename_mat=sprintf('%s%s%s.mat',options.txt,filesep,options.txt);
    sippi_verbose(sprintf('%s: Writing %s',mfilename,filename_mat),1);
    save(filename_mat);
end
%% PLOT
if options.lsq.plot==1;
    figure(71);clf;
    subplot(1,2,1);
    m{1}=m_est;
    sippi_plot_prior(prior,m,im,0,gca);
    colorbar
    subplot(1,2,2);
    m{1}=Cm_est_diag;
    sippi_plot_prior(prior,m,im,0,gca);
    if isfield(prior{im},'cax_var');
        caxis(prior{im}.cax_var);
    else
        caxis([0 max(m{1}(:))])
    end
    colorbar
    filename_png=sprintf('%s%s%s_mEst_CmEst.mat',options.txt,filesep,options.txt);
    print_mul(filename_png);
end

