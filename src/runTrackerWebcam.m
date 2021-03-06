clear all;
cam = webcam(1);

videoFrame = snapshot(cam);
frameSize = size(videoFrame);

videoPlayer = vision.VideoPlayer('Position', [100 100 [frameSize(2), frameSize(1)]+30]);

runLoop = true;

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


while(runLoop)
    img = snapshot(cam);
    imshow(img);
    rect = getrect;
    rect = floor(rect);
    close;
    runLoop = false;
    
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
        
        
        target = rect(3:4);
        target_disp = target;
        
        patch = getPatch(img, pos, motion_model_patch_size);
        
        motion_model_output_size = [floor(size(patch,1)/cell_size) floor(size(patch,2)/cell_size)];
        
        
        label_sigma = sqrt(prod(target_size)) * label_sigma/cell_size;
        
        
        % Rc
        yf = fft2(getLabelImage(motion_model_output_size(2), motion_model_output_size(1),label_sigma));
        
        cos_window = hann(motion_model_output_size(1)) * hann(motion_model_output_size(2))';
        
        xf = fft2(computeFeatures(patch, cell_size, cos_window));
        xkf = computeGaussianCorrelation(xf, xf, kernel_width);
        
        % Equation 2
        A = yf./(xkf + lambda);
        
        
            
        %Rt
        app_model_output_size = [floor(app_model_patch_size(1)/cell_size),...
         floor(app_model_patch_size(2)/cell_size)];
        
        yf_t = fft2(getLabelImage(app_model_output_size(2),app_model_output_size(1), label_sigma));
        
   %     cos_window_t = ones(size_y_t,size_x_t);
        
        patch = getPatch(img, pos, app_model_patch_size);
        xf_t = fft2(computeFeatures(patch, cell_size, []));
        xkf_t = computeGaussianCorrelation(xf_t, xf_t, kernel_width);
        
        % Equation 2
        A_t = yf_t./(xkf_t + lambda);
        
        %current_scale
        current_scale = 1;
        [scale_pyr,~] = scalePyramid(app_model_patch_size,N,img,pos,cell_size,scale_window,current_scale);
        
        sf = fft(scale_pyr,[],2);
        s_num = bsxfun(@times, ysf, conj(sf));
        s_den = sum(sf .* conj(sf), 1);
        
end

runLoop = true;

while(runLoop)
    img = snapshot(cam);
    img = rgb2gray(img);
        patch = getPatch(img, pos, motion_model_patch_size);
        
        zf = fft2(computeFeatures(patch, cell_size, cos_window));
        [diff,~] = getNewPos(zf, xf, A);
        pos = pos + cell_size * [diff(1) - floor(size(zf,1)/2)-1, diff(2) - floor(size(zf,2)/2)-1];
        
        patch = getPatch(img, pos, app_model_patch_size);
        zf_t = fft2(computeFeatures(patch, cell_size, []));
        [~,max_response] = getNewPos(zf_t, xf_t, A_t);
        
        %target
        %patch = getPatch(img, pos, app_model_patch_size);
        %zf_t = fft2(computeFeatures(patch, cell_size,[]));
        [scale_pyr,scale] = scalePyramid(app_model_patch_size,N,img,pos,cell_size,scale_window,current_scale);
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
    %runLoop = isOpen(videoPlayer);
    if(visualize == 1)
        %imshow(img); hold on;
        %rectangle('Position', [pos, patch_size], 'EdgeColor', 'r');
        %drawnow;
        bboxPolygon = [pos(2) - target_disp(2)/2, pos(1) - target_disp(1)/2,...
            pos(2) - target_disp(2)/2, pos(1) + target_disp(1)/2,...
            pos(2) + target_disp(2)/2, pos(1) + target_disp(1)/2,...
            pos(2) + target_disp(2)/2, pos(1) - target_disp(1)/2];
        img = insertShape(img, 'Polygon', bboxPolygon, 'LineWidth', 3);
        step(videoPlayer, img);
    end
end

clear cam;
release(videoPlayer);
