//
//  ViewController.m
//  TamplateMatching
//
//  Created by ChenYun on 2018/4/17.
//  Copyright © 2018年 ChenYun. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "TemplateMatch.h"


@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    TemplateMatch *templateMatch;
    CALayer *rectangleLayer;
}

@property (nonatomic,strong) AVCaptureSession *captureSession;
@property (nonatomic,strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic,strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //初始化模板匹配对象，并设置模板图
    templateMatch = [[TemplateMatch alloc] init];
    templateMatch.templateImage = [UIImage imageNamed:@"apple"];
    
    //检查视频权限，有授权则开始视频捕获
    [self checkAuthorization];
}

-(BOOL)shouldAutorotate{
    return NO;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//检查视频权限
- (void)checkAuthorization {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized) {
        [self setupCaptureSession];
    }
    else{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                [self setupCaptureSession];
            } else {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"未授权拍摄视频" message:@"请前往系统设置开放授权" preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {}];
                [alertController addAction:okAction];
                [self presentViewController:alertController animated:YES completion:nil];
                NSLog(@"Video access is not granted");
            }
        }];
    }
}

//配置视频并开始捕获
- (void)setupCaptureSession {
    NSArray *possibleDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *videoDevice = [possibleDevices firstObject];
    if (!videoDevice) return;
    
    // 创建Session
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];
    
    // 添加输入设备
    NSError *error = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    [session addInput:input];
    
    // 添加输出
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    dispatch_queue_t queue = dispatch_queue_create("SampleBufferQueue", NULL);
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    [session addOutput:self.videoOutput];
    
    // 完成配置
    [session commitConfiguration];
    self.captureSession = session;
    
    // 添加视频预览层
    self.videoPreviewLayer = [AVCaptureVideoPreviewLayer layer];
    self.videoPreviewLayer.frame = self.view.layer.bounds;
    self.videoPreviewLayer.session = session;
    [self.view.layer addSublayer:self.videoPreviewLayer];
    
    // 开始视频
    [session startRunning];
}

// 绘制标识框
- (void)drawRectangle:(CGRect)rect {
    if (rectangleLayer == nil) {
        rectangleLayer = [CALayer layer];
        rectangleLayer.frame = CGRectMake(0, 0, templateMatch.templateImage.size.width, templateMatch.templateImage.size.height);
        [rectangleLayer setBorderWidth:2.0];
        [rectangleLayer setBorderColor:[UIColor.redColor CGColor]];
        [self.view.layer addSublayer:rectangleLayer];
    }
    
    rectangleLayer.frame = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    rectangleLayer.hidden = NO;
}

// 隐藏标识框
- (void)hideRectangle {
    rectangleLayer.hidden = YES;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CGRect rect = [templateMatch matchWithSampleBuffer:sampleBuffer]; //将buffer提交给OpenCV进行模板匹配
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CGRectEqualToRect(rect,CGRectZero)) { //匹配成功，则绘制标识框
            [self drawRectangle:[self.videoPreviewLayer rectForMetadataOutputRectOfInterest:rect]]; //由于视频的尺寸和屏幕宽高比不一定一致，所以对于视频中的一个点坐标，需要转换到屏幕的对应位置中。
        }
        else{ //未匹配到，则隐藏标识框
            [self hideRectangle];
        }
    });
}

@end
