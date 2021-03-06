function runConvTracker(file_path)
% file_path should contain the path to the folder with the .jpg files

files = dir(strcat(file_path, '*.jpg'));
num_files = length(files);

lambda = 1e-4;
learning_rate = 0.01;
global kernel_width;
kernel_width = 1;
visualize = 1;
cell_size = 4;
label_sigma = 0.1;
global A_scale;
A_scale = 1.02;

global lambda_s;
lambda_s = 0.01;

motion_threshold = 0.15;
appearance_threshold = 0.38;

fileID = fopen('rects_conv.txt','w');


N = 33;
factor = 1/4;
scale_sigma = N/sqrt(N)*factor;
ss = (1:N) - ceil(N/2);
ys = exp(-0.5 * (ss.^2) / scale_sigma^2);
ysf = single(fft(ys));

if mod(N,2) == 0
    scale_window = single(hann(N+1));
    scale_window = scale_window(2:end);
else
    scale_window = single(hann(N));
end

% Add path to caffe
addpath('/Users/siddarth/Desktop/caffe/matlab');

caffe.set_mode_cpu();

% model_dir = '/Users/siddarth/Desktop/caffe/models/FCN/';
% net_weights = [model_dir 'fcn32s-heavy-pascal.caffemodel'];
% motion_proto = [model_dir 'deploy_motion.prototxt'];
% motion_app = [model_dir 'deploy_app.prototxt'];
global model_dir;
model_dir = '/Users/siddarth/Desktop/caffe/models/ResNet/';
net_weights = [model_dir 'ResNet-50-model.caffemodel'];
motion_proto = [model_dir 'ResNet-50-deploy-motion.prototxt'];
motion_app = [model_dir 'ResNet-50-deploy-app.prototxt'];
phase = 'test'; % run with phase test (so that dropout isn't applied)

net_motion = caffe.Net(motion_proto, net_weights, phase);
net_app = caffe.Net(motion_app, net_weights, phase);

global depth;
depth = 1;


avg_frame_rate = 0;

for i = 1:num_files
    
    % Read the next image
    current_image_name = files(i).name;
    current_image_path = strcat(file_path, current_image_name);
    img = imread(current_image_path);
    
    % If it is the first image, then prompt user to select the object to be
    % tracked
    start_time = clock();
    if(i == 1)

        imshow(img);
        rect = [198,214,34,81];
        %rect = [180,79,37,114];
%         rect = floor(getrect);
%         close;
%         
        temp = rect(1:2) + rect(3:4)/2;
        rect(1) = temp(2);
        rect(2) = temp(1);
        tempp = rect(3);
        rect(3) = rect(4);
        rect(4) = tempp;
       
        
        pos = rect(1:2);
        target_size = rect(3:4);
        
        motion_model_patch_size = floor(target_size.*[1.4 2.8]);
        
        app_model_patch_size = target_size + 8;
        
        net_motion.blobs('data').reshape([motion_model_patch_size(2)*depth,...
            motion_model_patch_size(1)*depth, 3, 1]); % reshape blob 'data'
        net_motion.reshape();

        net_app.blobs('data').reshape([app_model_patch_size(2)*depth,...
            app_model_patch_size(1)*depth, 3 1]); % reshape blob 'data'
        net_app.reshape();
        
        
        target = rect(3:4);
        target_disp = target;
        
        patch = getPatch(img, pos, motion_model_patch_size);     
        
        label_sigma = sqrt(prod(target_size)) * label_sigma/cell_size;
        
        % Rc
        xf = computeConvFeatures(patch, net_motion);
        motion_model_output_size = [size(xf, 1), size(xf,2)];
        
        yf = fft2(getLabelImage(motion_model_output_size(2), motion_model_output_size(1),label_sigma));
        
        cos_window = hann(motion_model_output_size(1)) * hann(motion_model_output_size(2))';
        
        xf = bsxfun(@times, xf, cos_window);
        xf = fft2(xf);
        
        xkf = computeGaussianCorrelation(xf, xf, kernel_width);
        % Equation 2
        A = yf./(xkf + lambda);
        
        
        patch = getPatch(img, pos, app_model_patch_size);
        xf_t = fft2(computeConvFeatures(patch, net_app));
        app_model_output_size = [size(xf_t, 1), size(xf_t,2)];
        yf_t = fft2(getLabelImage(app_model_output_size(2),app_model_output_size(1), label_sigma));
        xkf_t = computeGaussianCorrelation(xf_t, xf_t, kernel_width);
        
        % Equation 2
        A_t = yf_t./(xkf_t + lambda);
        
        %current_scale
        current_scale = 1;
        [scale_pyr,~] = convScalePyramid(app_model_patch_size,N,img,pos,cell_size,scale_window,current_scale, net_app);
        
        sf = fft(scale_pyr,[],2);
        s_num = bsxfun(@times, ysf, conj(sf));
        s_den = sum(sf .* conj(sf), 1);
        
        
        
    else
        net_motion.blobs('data').reshape([motion_model_patch_size(2)*depth,...
            motion_model_patch_size(1)*depth, 3, 1]); % reshape blob 'data'
        net_motion.reshape();

        net_app.blobs('data').reshape([app_model_patch_size(2)*depth,...
            app_model_patch_size(1)*depth, 3 1]); % reshape blob 'data'
        net_app.reshape();
       
        patch = getPatch(img, pos, motion_model_patch_size);
        
        zf = computeConvFeatures(patch, net_motion);
        zf = bsxfun(@times, zf, cos_window);
        zf = fft2(zf);
        [diff,~] = getNewPos(zf, xf, A);
        pos = pos + cell_size * [diff(1) - floor(size(zf,1)/2)-1, diff(2) - floor(size(zf,2)/2)-1];
        
        patch = getPatch(img, pos, app_model_patch_size);
        zf_t = fft2(computeConvFeatures(patch, net_app));
        [~,max_response] = getNewPos(zf_t, xf_t, A_t);
        
        %target
        %patch = getPatch(img, pos, app_model_patch_size);
        %zf_t = fft2(computeFeatures(patch, cell_size,[]));
        [scale_pyr,scale] = convScalePyramid(app_model_patch_size,N,img,pos,cell_size,scale_window,current_scale, net_app);
        [s,sf] = getOptimalScale(scale_pyr,scale,s_num,s_den);
        
        current_scale = current_scale*s;
        
        if current_scale > 5.2773
            current_scale = 5.2773;
        elseif current_scale<0.0534
            current_scale = 0.0534;
        end
        
        
        
        ns_num = bsxfun(@times, ysf, conj(sf));
        ns_den = sum(sf .* conj(sf), 1);


        target_disp = ceil(target*current_scale);
       

        
        zkf = computeGaussianCorrelation(zf, zf, kernel_width);
        A_z = yf./(zkf + lambda);
        
         % target
        xkf_t = computeGaussianCorrelation(zf_t, zf_t, kernel_width);
        A_n_t = yf_t./(xkf_t + lambda);
  
        
        % Equation 4
        xf = (1 - learning_rate) * xf + learning_rate * zf;
        A = (1 - learning_rate) * A + learning_rate * A_z;
        
         s_den = (1 - learning_rate) * s_den + learning_rate * ns_den;
        s_num = (1 - learning_rate) * s_num + learning_rate * ns_num;
        
        
        if(max_response > appearance_threshold)
            xf_t = (1 - learning_rate) * xf_t + learning_rate * zf_t;
            A_t = (1 - learning_rate) * A_t + learning_rate * A_n_t;    
        end
        

        
    end
    elapsed_time = etime(clock(), start_time);
    if(visualize == 1)
        imshow(imread(current_image_path)); hold on;
        rectangle('Position', [pos([2,1]) - target_disp([2,1])/2, target_disp([2,1])], 'EdgeColor', 'r');
        drawnow;
    end
    fprintf(fileID,'%d,%d,%d,%d\n', floor([pos([2,1]) - target_disp([2,1])/2, target_disp([2,1])]));
    avg_frame_rate = avg_frame_rate + 1/elapsed_time;
    disp(1/elapsed_time);
end

avg_frame_rate = avg_frame_rate/num_files
fclose(fileID);