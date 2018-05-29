//
//  TemplateMatch.cpp
//  OpenCVTest
//
//  Created by Yun CHEN on 2018/2/8.
//  Copyright © 2018年 Yun CHEN. All rights reserved.
//


#import "TemplateMatch.h"
#include <vector>
#include <math.h>



using namespace cv;
using namespace std;



@interface TemplateMatch() {
    UIImage *_templateImage;
    vector<Mat> _scaledTempls;
}

@end



@implementation TemplateMatch

static const float resizeRatio = 0.35;              //原图缩放比例，越小性能越好，但识别度越低
static const int maxTryTimes = 4;                   //未达到预定识别度时，再尝试的次数限制
static const float acceptableValue = 0.7;           //达到此识别度才被认为正确
static const float scaleRation = 0.75;              //当模板未被识别时，尝试放大/缩小模板。 指定每次模板缩小的比例

//设置模板图片
//由于拍摄会存在拉远拉近的行为，所以需要建立不同大小的模板图片，进行多次匹配
- (void)setTemplateImage:(UIImage *)templateImage {
    //保存默认模板图，并取得模板矩阵
    _templateImage = templateImage;
    Mat templUp = [self cvMatGrayFromUIImage:templateImage];
    
    //本例子默认采用竖屏拍摄，而AVFoundation提供的数据为横屏模式，所以需要将模板图逆时针旋转90度
    //更好的方式，是在ViewController中根据屏幕方向动态旋转模板图,并重新赋值。这里暂时简化处理。
    Mat templ;
    cv::rotate(templUp, templ, ROTATE_90_COUNTERCLOCKWISE);
    
    //设置新模板，需清空旧模板
    _scaledTempls.clear();
    
    //为了提高性能，模板图和原图进行同比列压缩
    Mat templResized;
    resize(templ, templResized, cv::Size(0, 0), resizeRatio, resizeRatio);
    _scaledTempls.push_back(templResized); //默认模板图也存放于模板数组中，以便循环匹配
    
    //由于模板图和原图大小比例不一致，需要放大缩小模板图，来多次比较。所以建立不同比例的模板图。
    for(int i=0;i<maxTryTimes;i++) {
        //放大模板图
        float powIncreaRation = pow(2 - scaleRation, i+1);
        resize(templ, templResized, cv::Size(0, 0), resizeRatio * powIncreaRation, resizeRatio * powIncreaRation);
        _scaledTempls.push_back(templResized); //由于push_back方法执行值拷贝，所以可以复用templResized变量。
        
        //缩小模板图
        float powReduceRation = pow(scaleRation, i+1);
        resize(templ, templResized, cv::Size(0, 0), resizeRatio * powReduceRation, resizeRatio * powReduceRation);
        _scaledTempls.push_back(templResized);
    }
}

//接受Buffer进行匹配
- (CGRect)matchWithSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    Mat img = [self cvMatFromBuffer:sampleBuffer]; //Buffer转换到矩阵
    
    //如果图片为空，则返回空值
    if (resizeRatio <= 0 || img.cols <= 0 || img.rows <= 0) {
        return CGRectZero;
    }
    
    //为了提高性能，将原图缩小。模板图也已同比例缩小。
    Mat imgResized = Mat();
    resize(img, imgResized, cv::Size(0, 0), resizeRatio, resizeRatio);
    
    //进行匹配
    cv::Rect rect = [self matchWithMat:imgResized];

    //除以行列数得到点位置在全图中的比例，转为AVCapture Metadata的坐标系统
    CGPoint point = CGPointMake(rect.x / CGFloat(imgResized.cols), rect.y  / CGFloat(imgResized.rows));
    CGSize templSize = CGSizeMake(rect.width / CGFloat(imgResized.cols), rect.height / CGFloat(imgResized.rows));
    
    return CGRectMake(point.x, point.y, templSize.width, templSize.height);
}

//调用OpenCV进行匹配
//此方法具体解释参考OpenCV官方文档: https://docs.opencv.org/3.2.0/de/da9/tutorial_template_matching.html
- (cv::Rect)matchWithMat:(Mat)img {
    double minVal;
    double maxVal;
    cv::Point minLoc;
    cv::Point maxLoc;

    //匹配不同大小的模板图
    for (int i=0; i < _scaledTempls.size(); i++) {
        Mat templ = _scaledTempls[i];
        
        //创建结果矩阵，用于存放单次匹配到的位置信息(单次会匹配到很多，后面根据不同算法取最大或最小值)
        int result_cols = img.cols - templ.cols + 1;
        int result_rows = img.rows - templ.rows + 1;
        Mat result;
        result.create(result_rows, result_cols, CV_32FC1);
        
        //OpenCV匹配
        matchTemplate(img, templ, result, TM_CCOEFF_NORMED);
        
        //整理出本次匹配的最大最小值
        minMaxLoc(result, &minVal, &maxVal, &minLoc, &maxLoc, Mat());
        
        //TM_CCOEFF_NORMED算法，取最大值为最佳匹配
        //当最大值符合要求，认为匹配成功
        if (maxVal >= acceptableValue) {
            NSLog(@"matched point:%d,%d maxVal:%f, tried times:%d",maxLoc.x,maxLoc.y,maxVal,i + 1);
            return cv::Rect(maxLoc,cv::Size(templ.rows,templ.cols));
        }
    }
    
    //未匹配到，则返回空区域
    return cv::Rect();
}

//UIImage转为OpenCV灰图矩阵
- (Mat)cvMatGrayFromUIImage:(UIImage *)image {
    Mat img;
    Mat img_color = [self cvMatFromUIImage:image];
    cvtColor(img_color, img, CV_BGR2GRAY);
    
    return img;
}

//UIImage转为OpenCV矩阵
- (Mat)cvMatFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    Mat cvMat(rows, cols, CV_8UC4); // 8位图, 4通道 (颜色 通道 + alpha)
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // 数据来源
                                                    cols,                       // 宽
                                                    rows,                       // 高
                                                    8,                          // 8位
                                                    cvMat.step[0],              // 每行字节
                                                    colorSpace,                 // 颜色空间
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap图信息
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

//Buffer转为OpenCV矩阵
- (Mat)cvMatFromBuffer:(CMSampleBufferRef)buffer {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    //取得高宽，以及数据起始地址
    int bufferWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int bufferHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    unsigned char *pixel = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
    
    //转为OpenCV矩阵
    Mat mat = Mat(bufferHeight,bufferWidth,CV_8UC4,pixel,CVPixelBufferGetBytesPerRow(pixelBuffer));
    
    //结束处理
    CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
    
    //转为灰度图矩阵
    Mat matGray;
    cvtColor(mat, matGray, CV_BGR2GRAY);
    
    return matGray;
}


@end




