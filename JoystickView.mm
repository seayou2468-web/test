#import "JoystickView.h"

@interface JoystickView () {
    UIView *_stick;
    UIView *_base;
    BOOL _setupDone;
}
@end

@implementation JoystickView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    _setupDone = NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_setupDone) {
        [self setupUI];
        _setupDone = YES;
    }

    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    _base.frame = CGRectMake(0, 0, size, size);
    _base.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    _base.layer.cornerRadius = size / 2;

    CGFloat stickSize = size * 0.4;
    _stick.frame = CGRectMake(0, 0, stickSize, stickSize);
    _stick.center = _base.center;
    _stick.layer.cornerRadius = stickSize / 2;
}

- (void)setupUI {
    _base = [[UIView alloc] init];
    _base.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    _base.layer.borderWidth = 2;
    _base.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    _base.userInteractionEnabled = NO;
    [self addSubview:_base];

    _stick = [[UIView alloc] init];
    _stick.backgroundColor = [UIColor systemBlueColor];
    _stick.layer.shadowColor = [UIColor blackColor].CGColor;
    _stick.layer.shadowOffset = CGSizeZero;
    _stick.layer.shadowRadius = 4;
    _stick.layer.shadowOpacity = 0.5;
    _stick.userInteractionEnabled = NO;
    [self addSubview:_stick];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouches:touches];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouches:touches];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [UIView animateWithDuration:0.2 animations:^{
        self->_stick.center = self->_base.center;
    }];
    [self.delegate joystickDidRelease];
}

- (void)handleTouches:(NSSet<UITouch *> *)touches {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];

    CGPoint center = _base.center;
    CGFloat distance = sqrt(pow(location.x - center.x, 2) + pow(location.y - center.y, 2));
    CGFloat radius = _base.bounds.size.width / 2;

    if (distance > radius) {
        CGFloat theta = atan2(location.y - center.y, location.x - center.x);
        location.x = center.x + radius * cos(theta);
        location.y = center.y + radius * sin(theta);
    }

    _stick.center = location;

    CGPoint offset = CGPointMake((location.x - center.x) / (radius > 0 ? radius : 1), (location.y - center.y) / (radius > 0 ? radius : 1));
    [self.delegate joystickDidMoveWithOffset:offset];
}

@end
