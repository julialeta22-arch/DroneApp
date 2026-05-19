const ComponentFunction = function() {
// @section:imports @depends:[]
var React = require('react');
var useState = React.useState;
var useEffect = React.useEffect;
var useRef = React.useRef;
var useMemo = React.useMemo;
var useCallback = React.useCallback;
var useContext = React.useContext;
var RN = require('react-native');
var View = RN.View;
var Text = RN.Text;
var StyleSheet = RN.StyleSheet;
var TouchableOpacity = RN.TouchableOpacity;
var ScrollView = RN.ScrollView;
var FlatList = RN.FlatList;
var Alert = RN.Alert;
var Platform = RN.Platform;
var StatusBar = RN.StatusBar;
var ActivityIndicator = RN.ActivityIndicator;
var PanResponder = RN.PanResponder;
var Dimensions = RN.Dimensions;
var Modal = RN.Modal;
var TextInput = RN.TextInput;
var MaterialIcons = require('@expo/vector-icons').MaterialIcons;
var createBottomTabNavigator = require('@react-navigation/bottom-tabs').createBottomTabNavigator;
var useSafeAreaInsets = require('react-native-safe-area-context').useSafeAreaInsets;
var { BLEProvider, useBLE } = require('./src/BLEContext');
// @end:imports

// @section:theme @depends:[]
var primaryColor = '#1E40AF';
var accentColor = '#3B82F6';
var backgroundColor = '#0A0F1E';
var cardColor = '#0F1E3C';
var surfaceColor = '#162447';
var textPrimary = '#E2E8F0';
var textSecondary = '#94A3B8';
var successColor = '#10B981';
var dangerColor = '#EF4444';
var warningColor = '#F59E0B';
var borderColor = '#1E3A6E';
var TAB_MENU_HEIGHT = Platform.OS === 'web' ? 56 : 49;
var SCROLL_EXTRA_PADDING = 16;
var WEB_TAB_MENU_PADDING = 90;
var FAB_SPACING = 16;
var STICK_SIZE = 200;
var STICK_KNOB_SIZE = 60;
var STICK_SIZE_LAND = 170;
var STICK_KNOB_SIZE_LAND = 52;
var VERTICAL_SLIDER_WIDTH = 70;
var VERTICAL_SLIDER_HEIGHT = 300;
var VERTICAL_SLIDER_HEIGHT_LAND = 200;
var BLE_SERVICE_UUID = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
var BLE_CHAR_UUID_RX = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
var BLE_CHAR_UUID_TX = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
var clamp = function(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; };
// @end:theme

// @section:utils @depends:[]
var stringToBytes = function(str) {
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    bytes.push(str.charCodeAt(i) & 0xFF);
  }
  return bytes;
};
var getOrientation = function() {
  var dim = Dimensions.get('window');
  return dim.width > dim.height ? 'landscape' : 'portrait';
};
// @end:utils

// @section:navigation-setup @depends:[]
var Tab = createBottomTabNavigator();
// @end:navigation-setup

// @section:ThemeContext @depends:[theme]
var ThemeContext = React.createContext(null);
var ThemeProvider = function(props) {
  var themeValue = useMemo(function() {
    return {
      colors: {
        primary: primaryColor, accent: accentColor,
        background: backgroundColor, card: cardColor,
        surface: surfaceColor, text: textPrimary,
        textSecondary: textSecondary, border: borderColor,
        success: successColor, danger: dangerColor, warning: warningColor
      }
    };
  }, []);
  return React.createElement(ThemeContext.Provider, { testID: 'Provider-1', value: themeValue }, props.children);
};
var useTheme = function() { return useContext(ThemeContext); };
// @end:ThemeContext

// @section:OrientationContext @depends:[]
var OrientationContext = React.createContext({ orientation: 'portrait', autoRotate: true, toggleAutoRotate: function() {} });
var OrientationProvider = function(props) {
  var orientationState = useState(getOrientation());
  var orientation = orientationState[0];
  var setOrientation = orientationState[1];
  var autoRotateState = useState(true);
  var autoRotate = autoRotateState[0];
  var setAutoRotate = autoRotateState[1];

  useEffect(function() {
    var handler = function(dims) {
      if (autoRotate) {
        var w = dims.window.width;
        var h = dims.window.height;
        setOrientation(w > h ? 'landscape' : 'portrait');
      }
    };
    var sub = Dimensions.addEventListener('change', handler);
    return function() { if (sub && sub.remove) { sub.remove(); } };
  }, [autoRotate]);

  var toggleAutoRotate = useCallback(function() {
    setAutoRotate(function(prev) {
      if (prev) { setOrientation('portrait'); } else { setOrientation(getOrientation()); }
      return !prev;
    });
  }, []);

  var value = useMemo(function() {
    return { orientation: orientation, autoRotate: autoRotate, toggleAutoRotate: toggleAutoRotate };
  }, [orientation, autoRotate, toggleAutoRotate]);

  return React.createElement(OrientationContext.Provider, { testID: 'Provider-2', value: value }, props.children);
};
var useOrientation = function() { return useContext(OrientationContext); };
// @end:OrientationContext

// @section:BLEContext @depends:[]
// BLE functionality is now in ./src/BLEContext.js
// useBLE() is imported from there
// @end:BLEContext

// @section:VirtualStick @depends:[theme]
var VirtualStick = function(props) {
  var value = props.value;
  var onValueChange = props.onValueChange;
  var label = props.label;
  var color = props.color || accentColor;
  var componentId = props.componentId || 'stick';
  var disabled = props.disabled || false;
  var compact = props.compact || false;

  var stickSize = compact ? STICK_SIZE_LAND : STICK_SIZE;
  var knobSize = compact ? STICK_KNOB_SIZE_LAND : STICK_KNOB_SIZE;

  var offsetState = useState({ x: 0, y: 0 });
  var offset = offsetState[0];
  var setOffset = offsetState[1];
  var activeState = useState(false);
  var isActive = activeState[0];
  var setIsActive = activeState[1];

  var maxOffset = (stickSize - knobSize) / 2;
  var onValueChangeRef = useRef(onValueChange);
  var disabledRef = useRef(disabled);
  var maxOffsetRef = useRef(maxOffset);
  var stickSizeRef = useRef(stickSize);
  var knobSizeRef = useRef(knobSize);

  useEffect(function() { onValueChangeRef.current = onValueChange; }, [onValueChange]);
  useEffect(function() { disabledRef.current = disabled; }, [disabled]);
  useEffect(function() { maxOffsetRef.current = (stickSizeRef.current - knobSizeRef.current) / 2; }, [stickSize, knobSize]);
  useEffect(function() { stickSizeRef.current = stickSize; knobSizeRef.current = knobSize; }, [stickSize, knobSize]);

  var panRef = useRef(null);
  if (!panRef.current) {
    panRef.current = PanResponder.create({
      onStartShouldSetPanResponder: function() { return !disabledRef.current; },
      onStartShouldSetPanResponderCapture: function() { return !disabledRef.current; },
      onMoveShouldSetPanResponder: function() { return !disabledRef.current; },
      onMoveShouldSetPanResponderCapture: function() { return !disabledRef.current; },
      onPanResponderGrant: function() { setIsActive(true); },
      onPanResponderMove: function(evt, gs) {
        var mo = maxOffsetRef.current;
        var dx = clamp(gs.dx, -mo, mo);
        var dy = clamp(gs.dy, -mo, mo);
        setOffset({ x: dx, y: dy });
        if (onValueChangeRef.current) { onValueChangeRef.current({ x: dx / mo, y: -(dy / mo) }); }
      },
      onPanResponderRelease: function() {
        setOffset({ x: 0, y: 0 });
        setIsActive(false);
        if (onValueChangeRef.current) { onValueChangeRef.current({ x: 0, y: 0 }); }
      },
      onPanResponderTerminate: function() {
        setOffset({ x: 0, y: 0 });
        setIsActive(false);
        if (onValueChangeRef.current) { onValueChangeRef.current({ x: 0, y: 0 }); }
      }
    });
  }

  var knobCenterLeft = (stickSize / 2) - (knobSize / 2) + offset.x;
  var knobCenterTop = (stickSize / 2) - (knobSize / 2) + offset.y;
  var activeColor = disabled ? borderColor : color;
  var glowOpacity = isActive ? 0.45 : 0.18;
  var distFromCenter = Math.sqrt(offset.x * offset.x + offset.y * offset.y);
  var maxDist = maxOffset * Math.sqrt(2);
  var normalizedDist = Math.min(distFromCenter / Math.max(maxDist, 1), 1);
  var ringScale = 1 + normalizedDist * 0.18;

  return React.createElement(View, { testID: 'View-1', style: { alignItems: 'center' }, componentId: componentId },
    React.createElement(Text, { testID: 'Text-1', style: { color: textSecondary, fontSize: compact ? 9 : 11, fontWeight: '700', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: compact ? 6 : 10 } }, label),
    React.createElement(View, Object.assign({}, Object.assign({}, panRef.current.panHandlers, {
      style: {
        width: stickSize, height: stickSize,
        backgroundColor: disabled ? surfaceColor + 'AA' : surfaceColor,
        borderRadius: stickSize / 2,
        borderWidth: isActive ? 2.5 : 2,
        borderColor: isActive ? activeColor : borderColor,
        overflow: 'visible',
        justifyContent: 'center', alignItems: 'center',
        shadowColor: isActive ? activeColor : 'transparent',
        shadowOpacity: isActive ? 0.5 : 0,
        shadowRadius: 16,
        elevation: isActive ? 10 : 2
      },
      componentId: componentId + '-base'
    }), { testID: 'View-2' }),
      React.createElement(View, { testID: 'View-3', style: { position: 'absolute', width: 1.5, height: stickSize * 0.7, top: stickSize * 0.15, left: stickSize / 2 - 0.75, backgroundColor: borderColor, opacity: 0.6 } }),
      React.createElement(View, { testID: 'View-4', style: { position: 'absolute', height: 1.5, width: stickSize * 0.7, left: stickSize * 0.15, top: stickSize / 2 - 0.75, backgroundColor: borderColor, opacity: 0.6 } }),
      React.createElement(View, { testID: 'View-5', style: { position: 'absolute', width: stickSize * 0.55, height: stickSize * 0.55, borderRadius: stickSize * 0.275, borderWidth: 1, borderColor: activeColor, opacity: 0.12, top: stickSize * 0.225, left: stickSize * 0.225 } }),
      React.createElement(View, { testID: 'View-6', style: { position: 'absolute', width: stickSize * 0.28, height: stickSize * 0.28, borderRadius: stickSize * 0.14, borderWidth: 1, borderColor: activeColor, opacity: 0.18, top: stickSize * 0.36, left: stickSize * 0.36 } }),
      React.createElement(View, { testID: 'View-7', componentId: componentId + '-knob-glow', style: { position: 'absolute', width: knobSize + 28, height: knobSize + 28, borderRadius: (knobSize + 28) / 2, backgroundColor: activeColor, opacity: glowOpacity, left: knobCenterLeft - 14, top: knobCenterTop - 14, transform: [{ scale: ringScale }] } }),
      React.createElement(View, { testID: 'View-8', componentId: componentId + '-knob-outer', style: { position: 'absolute', width: knobSize, height: knobSize, borderRadius: knobSize / 2, backgroundColor: disabled ? surfaceColor : primaryColor, left: knobCenterLeft, top: knobCenterTop, borderWidth: 2.5, borderColor: activeColor, shadowColor: activeColor, shadowOpacity: isActive ? 0.9 : 0.4, shadowRadius: isActive ? 14 : 8, elevation: isActive ? 14 : 6, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' } },
        React.createElement(View, { testID: 'View-9', style: { width: knobSize * 0.72, height: knobSize * 0.72, borderRadius: knobSize * 0.36, backgroundColor: isActive ? activeColor : activeColor + '55', alignItems: 'center', justifyContent: 'center' } },
          React.createElement(View, { testID: 'View-10', style: { width: knobSize * 0.35, height: knobSize * 0.35, borderRadius: knobSize * 0.175, backgroundColor: isActive ? '#FFFFFF' : activeColor + 'AA', opacity: isActive ? 0.9 : 0.6 } })
        )
      )
    ),
    React.createElement(View, { testID: 'View-11', style: { flexDirection: 'row', marginTop: compact ? 6 : 10, justifyContent: 'space-around', width: stickSize } },
      React.createElement(View, { testID: 'View-12', style: { alignItems: 'center', backgroundColor: surfaceColor, borderRadius: 8, paddingHorizontal: compact ? 6 : 10, paddingVertical: compact ? 3 : 5, minWidth: 56 } },
        React.createElement(Text, { testID: 'Text-2', style: { color: textSecondary, fontSize: 9, fontWeight: '700', letterSpacing: 1 } }, 'X'),
        React.createElement(Text, { testID: 'Text-3', style: { color: activeColor, fontSize: compact ? 12 : 14, fontWeight: 'bold', fontFamily: Platform.OS === 'ios' ? 'Courier New' : 'monospace' } }, (value.x || 0).toFixed(2))
      ),
      React.createElement(View, { testID: 'View-13', style: { alignItems: 'center', backgroundColor: surfaceColor, borderRadius: 8, paddingHorizontal: compact ? 6 : 10, paddingVertical: compact ? 3 : 5, minWidth: 56 } },
        React.createElement(Text, { testID: 'Text-4', style: { color: textSecondary, fontSize: 9, fontWeight: '700', letterSpacing: 1 } }, 'Y'),
        React.createElement(Text, { testID: 'Text-5', style: { color: activeColor, fontSize: compact ? 12 : 14, fontWeight: 'bold', fontFamily: Platform.OS === 'ios' ? 'Courier New' : 'monospace' } }, (value.y || 0).toFixed(2))
      )
    )
  );
};
// @end:VirtualStick

// @section:VerticalThrottle @depends:[theme]
var VerticalThrottle = function(props) {
  var value = props.value;
  var onValueChange = props.onValueChange;
  var disabled = props.disabled || false;
  var componentId = props.componentId || 'throttle';
  var compact = props.compact || false;

  var sliderHeight = compact ? VERTICAL_SLIDER_HEIGHT_LAND : VERTICAL_SLIDER_HEIGHT;

  var activeState = useState(false);
  var isActive = activeState[0];
  var setIsActive = activeState[1];

  var trackLayoutRef = useRef({ pageY: 0, height: sliderHeight });
  var trackViewRef = useRef(null);
  var onValueChangeRef = useRef(onValueChange);
  var disabledRef = useRef(disabled);
  var sliderHeightRef = useRef(sliderHeight);

  useEffect(function() { onValueChangeRef.current = onValueChange; }, [onValueChange]);
  useEffect(function() { disabledRef.current = disabled; }, [disabled]);
  useEffect(function() { sliderHeightRef.current = sliderHeight; }, [sliderHeight]);

  var measureTrack = function(callback) {
    if (trackViewRef.current && trackViewRef.current.measure) {
      trackViewRef.current.measure(function(fx, fy, width, height, pageX, pageY) {
        trackLayoutRef.current = { pageY: pageY, height: height > 0 ? height : sliderHeightRef.current };
        if (callback) { callback(); }
      });
    } else {
      if (callback) { callback(); }
    }
  };

  var applyPageY = function(pageY) {
    var layout = trackLayoutRef.current;
    var h = layout.height;
    var top = layout.pageY;
    if (h <= 0) return;
    var relY = pageY - top;
    var v = clamp(Math.round((1 - relY / h) * 255), 0, 255);
    if (onValueChangeRef.current) { onValueChangeRef.current(v); }
  };

  var panRef = useRef(null);
  if (!panRef.current) {
    panRef.current = PanResponder.create({
      onStartShouldSetPanResponder: function() { return !disabledRef.current; },
      onStartShouldSetPanResponderCapture: function() { return !disabledRef.current; },
      onMoveShouldSetPanResponder: function() { return !disabledRef.current; },
      onMoveShouldSetPanResponderCapture: function() { return !disabledRef.current; },
      onPanResponderGrant: function(evt) {
        setIsActive(true);
        measureTrack(function() { applyPageY(evt.nativeEvent.pageY); });
      },
      onPanResponderMove: function(evt) { applyPageY(evt.nativeEvent.pageY); },
      onPanResponderRelease: function() { setIsActive(false); },
      onPanResponderTerminate: function() { setIsActive(false); }
    });
  }

  var fillRatio = value / 255;
  var fillH = Math.max(4, fillRatio * (sliderHeight - 6));
  var throttlePercent = Math.round(fillRatio * 100);
  var color = disabled ? borderColor : accentColor;
  var thumbTopOffset = (1 - fillRatio) * (sliderHeight - 6) + 3 - 16;

  return React.createElement(View, { testID: 'View-14', style: { alignItems: 'center' }, componentId: componentId },
    React.createElement(Text, { testID: 'Text-6', style: { color: textSecondary, fontSize: compact ? 9 : 10, fontWeight: '800', letterSpacing: 2, textTransform: 'uppercase', marginBottom: compact ? 6 : 10 } }, 'THR'),
    React.createElement(View, { testID: 'View-15', style: { position: 'relative', height: sliderHeight + 32 } },
      React.createElement(View, Object.assign({}, Object.assign({}, panRef.current.panHandlers, {
        ref: trackViewRef,
        onLayout: function() { measureTrack(null); },
        style: { width: VERTICAL_SLIDER_WIDTH, height: sliderHeight, backgroundColor: surfaceColor, borderRadius: 16, borderWidth: isActive ? 2.5 : 2, borderColor: isActive ? color : borderColor, overflow: 'hidden', justifyContent: 'flex-end', shadowColor: isActive ? color : 'transparent', shadowOpacity: isActive ? 0.6 : 0, shadowRadius: 12, elevation: isActive ? 10 : 2 },
        componentId: componentId + '-track'
      }), { testID: 'View-16' }),
        React.createElement(View, { testID: 'View-17', style: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, justifyContent: 'center', alignItems: 'center' } },
          React.createElement(Text, { testID: 'Text-7', style: { color: disabled ? textSecondary : '#FFFFFF', fontSize: 12, fontWeight: '800', opacity: disabled ? 0.35 : 0.55, letterSpacing: 1 } }, throttlePercent + '%')
        ),
        React.createElement(View, { testID: 'View-18', style: { width: '100%', height: fillH, backgroundColor: primaryColor, opacity: disabled ? 0.25 : 0.85, borderRadius: 14 }, componentId: componentId + '-fill' }),
        React.createElement(View, { testID: 'View-19', style: { position: 'absolute', width: VERTICAL_SLIDER_WIDTH * 0.3, height: 1, backgroundColor: color, opacity: 0.15, top: sliderHeight * 0.25, left: VERTICAL_SLIDER_WIDTH * 0.35 } }),
        React.createElement(View, { testID: 'View-20', style: { position: 'absolute', width: VERTICAL_SLIDER_WIDTH * 0.3, height: 1, backgroundColor: color, opacity: 0.15, top: sliderHeight * 0.5, left: VERTICAL_SLIDER_WIDTH * 0.35 } }),
        React.createElement(View, { testID: 'View-21', style: { position: 'absolute', width: VERTICAL_SLIDER_WIDTH * 0.3, height: 1, backgroundColor: color, opacity: 0.15, top: sliderHeight * 0.75, left: VERTICAL_SLIDER_WIDTH * 0.35 } })
      ),
      React.createElement(View, { testID: 'View-22', pointerEvents: 'none', style: { position: 'absolute', left: -10, top: thumbTopOffset, width: VERTICAL_SLIDER_WIDTH + 20, height: 32, alignItems: 'center', justifyContent: 'center' }, componentId: componentId + '-thumb-row' },
        React.createElement(View, { testID: 'View-23', style: { width: VERTICAL_SLIDER_WIDTH + 20, height: 32, borderRadius: 10, backgroundColor: disabled ? surfaceColor : primaryColor, borderWidth: isActive ? 2 : 1.5, borderColor: isActive ? '#FFFFFF' : color, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', shadowColor: color, shadowOpacity: isActive ? 0.8 : 0.3, shadowRadius: isActive ? 10 : 5, elevation: isActive ? 10 : 4 } },
          React.createElement(View, { testID: 'View-24', style: { width: 22, height: 3, borderRadius: 2, backgroundColor: isActive ? '#FFFFFF' : color, marginHorizontal: 2 } }),
          React.createElement(View, { testID: 'View-25', style: { width: 22, height: 3, borderRadius: 2, backgroundColor: isActive ? '#FFFFFF' : color, marginHorizontal: 2 } }),
          React.createElement(View, { testID: 'View-26', style: { width: 22, height: 3, borderRadius: 2, backgroundColor: isActive ? '#FFFFFF' : color, marginHorizontal: 2 } })
        )
      )
    ),
    React.createElement(View, { testID: 'View-27', style: { backgroundColor: isActive ? primaryColor : surfaceColor, borderRadius: 10, paddingHorizontal: 12, paddingVertical: 6, marginTop: 4, minWidth: 56, alignItems: 'center', borderWidth: 1, borderColor: isActive ? color : borderColor } },
      React.createElement(Text, { testID: 'Text-8', style: { color: isActive ? '#FFFFFF' : color, fontSize: compact ? 14 : 16, fontWeight: 'bold', fontFamily: Platform.OS === 'ios' ? 'Courier New' : 'monospace' } }, String(value))
    )
  );
};
// @end:VerticalThrottle

// @section:PresetsModal @depends:[theme]
var PresetsModal = function(props) {
  var visible = props.visible;
  var onClose = props.onClose;
  var onSelect = props.onSelect;
  var insetsTop = props.insetsTop;
  var insetsBottom = props.insetsBottom;

  var PRESETS = [
    { name: 'IDLE', icon: 'power-settings-new', throttle: 0, elevator: 90, aileron: 90, color: textSecondary },
    { name: 'HOVER', icon: 'flight', throttle: 128, elevator: 90, aileron: 90, color: successColor },
    { name: 'CLIMB', icon: 'north', throttle: 200, elevator: 120, aileron: 90, color: warningColor },
    { name: 'DESCEND', icon: 'south', throttle: 80, elevator: 60, aileron: 90, color: accentColor },
    { name: 'BANK L', icon: 'rotate-left', throttle: 128, elevator: 90, aileron: 60, color: '#A78BFA' },
    { name: 'BANK R', icon: 'rotate-right', throttle: 128, elevator: 90, aileron: 120, color: '#F472B6' }
  ];

  return React.createElement(Modal, { testID: 'Modal-1', visible: visible, animationType: 'slide', transparent: true, onRequestClose: onClose },
    React.createElement(View, { testID: 'View-28', style: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.75)', marginTop: insetsTop }, componentId: 'presets-overlay' },
      React.createElement(View, { testID: 'View-29', style: { backgroundColor: cardColor, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, paddingBottom: insetsBottom + 20, borderTopWidth: 1, borderColor: borderColor }, componentId: 'presets-sheet' },
        React.createElement(View, { testID: 'View-30', style: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 } },
          React.createElement(Text, { testID: 'Text-9', style: { color: textPrimary, fontSize: 18, fontWeight: 'bold', letterSpacing: 1 } }, 'FLIGHT PRESETS'),
          React.createElement(TouchableOpacity, { testID: 'TouchableOpacity-1', onPress: onClose, componentId: 'presets-close' },
            React.createElement(MaterialIcons, { testID: 'MaterialIcons-1', name: 'close', size: 24, color: textSecondary })
          )
        ),
        React.createElement(View, { testID: 'View-31', style: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' } },
          PRESETS.map(function(preset, idx) {
            return React.createElement(TouchableOpacity, { testID: 'TouchableOpacity-2', key: String(idx), onPress: function() { onSelect(preset); },
              style: { width: '48%', backgroundColor: surfaceColor, borderRadius: 14, padding: 16, marginBottom: 10, borderWidth: 1, borderColor: preset.color + '55', alignItems: 'center' },
              componentId: 'preset-btn-' + idx
            },
              React.createElement(View, { testID: 'View-32', style: { width: 44, height: 44, borderRadius: 22, backgroundColor: preset.color + '22', alignItems: 'center', justifyContent: 'center', marginBottom: 8 } },
                React.createElement(MaterialIcons, { testID: 'MaterialIcons-2', name: preset.icon, size: 24, color: preset.color })
              ),
              React.createElement(Text, { testID: 'Text-10', style: { color: preset.color, fontSize: 12, fontWeight: 'bold', letterSpacing: 1.5 } }, preset.name),
              React.createElement(Text, { testID: 'Text-11', style: { color: textSecondary, fontSize: 10, marginTop: 4 } }, 'T:' + preset.throttle + ' E:' + preset.elevator + ' A:' + preset.aileron)
            );
          })
        )
      )
    )
  );
};
// @end:PresetsModal

// @section:BLEModal @depends:[theme,BLEContext]
var BLEConnectionModal = function(props) {
  var visible = props.visible;
  var onClose = props.onClose;
  var insetsTop = props.insetsTop;
  var insetsBottom = props.insetsBottom;
  var ble = useBLE();

  var scanningState = useState(false);
  var scanning = scanningState[0];
  var setScanning = scanningState[1];
  var devicesState = useState([]);
  var devices = devicesState[0];
  var setDevices = devicesState[1];
  var connectingIdState = useState(null);
  var connectingId = connectingIdState[0];
  var setConnectingId = connectingIdState[1];
  var statusMsgState = useState('');
  var statusMsg = statusMsgState[0];
  var setStatusMsg = statusMsgState[1];

  useEffect(function() {
    if (!visible) {
      setDevices([]);
      setStatusMsg('');
      setScanning(false);
      setConnectingId(null);
    }
  }, [visible]);

  var doScan = useCallback(function() {
    if (!ble || !ble.bt || !ble.bt.scan) {
      setStatusMsg('Bluetooth not available on this platform');
      return;
    }
    setScanning(true);
    setDevices([]);
    setStatusMsg('Scanning for devices...');
    ble.bt.scan({ timeout: 8000 }).then(function(result) {
      setScanning(false);
      if (Array.isArray(result)) {
        setDevices(result);
        setStatusMsg('Found ' + result.length + ' device(s)');
      } else if (result && result.error) {
        setStatusMsg('Scan error: ' + result.error);
      } else {
        setStatusMsg('Scan complete');
      }
    }).catch(function(err) {
      setScanning(false);
      setStatusMsg('Scan failed: ' + (err && err.message ? err.message : 'Unknown error'));
    });
  }, [ble]);

  var doConnect = useCallback(function(device) {
    setConnectingId(device.id);
    setStatusMsg('Connecting to ' + (device.name || device.id) + '...');
    ble.connectToDevice(device).then(function() {
      setConnectingId(null);
      setStatusMsg('Connected!');
      setTimeout(onClose, 800);
    }).catch(function(err) {
      setConnectingId(null);
      setStatusMsg('Failed: ' + (err && err.message ? err.message : 'Connection error'));
    });
  }, [ble, onClose]);

  var doDisconnect = useCallback(function() {
    ble.disconnectFromDevice().then(function() { setStatusMsg('Disconnected'); }).catch(function() {});
  }, [ble]);

  var isConnected = ble && ble.connectedDevice;

  return React.createElement(Modal, { testID: 'Modal-2', visible: visible, animationType: 'slide', transparent: true, onRequestClose: onClose },
    React.createElement(View, { testID: 'View-33', style: { flex: 1, backgroundColor: 'rgba(0,0,0,0.8)', marginTop: insetsTop }, componentId: 'ble-modal-overlay' },
      React.createElement(View, { testID: 'View-34', style: { flex: 1, backgroundColor: backgroundColor, paddingTop: 16 } },
        React.createElement(View, { testID: 'View-35', style: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingBottom: 16, borderBottomWidth: 1, borderColor: borderColor } },
          React.createElement(View, { testID: 'View-36', style: { flex: 1 } },
            React.createElement(Text, { testID: 'Text-12', style: { color: textPrimary, fontSize: 18, fontWeight: 'bold', letterSpacing: 1 } }, 'BLE DEVICES'),
            React.createElement(Text, { testID: 'Text-13', style: { color: textSecondary, fontSize: 11, marginTop: 2 } }, 'Select a device to connect')
          ),
          React.createElement(TouchableOpacity, { testID: 'TouchableOpacity-3', onPress: onClose, componentId: 'ble-modal-close' },
            React.createElement(MaterialIcons, { testID: 'MaterialIcons-3', name: 'close', size: 26, color: textSecondary })
          )
        ),
        isConnected
          ? React.createElement(View, { testID: 'View-37', style: { margin: 16, padding: 14, backgroundColor: successColor + '22', borderRadius: 12, borderWidth: 1, borderColor: successColor + '55', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, componentId: 'connected-banner' },
              React.createElement(View, { testID: 'View-38', style: { flex: 1 } },
                React.createElement(View, { testID: 'View-39', style: { flexDirection: 'row', alignItems: 'center', marginBottom: 2 } },
                  React.createElement(View, { testID: 'View-40', style: { width: 7, height: 7, borderRadius: 3.5, backgroundColor: successColor, marginRight: 6 } }),
                  React.createElement(Text, { testID: 'Text-14', style: { color: successColor, fontSize: 13, fontWeight: '700', letterSpacing: 0.5 } }, 'CONNECTED')
                ),
                React.createElement(Text, { testID: 'Text-15', style: { color: textSecondary, fontSize: 12, marginTop: 2 } }, ble.connectedDevice.name || ble.connectedDevice.id)
              ),
              React.createElement(TouchableOpacity, { testID: 'TouchableOpacity-4', onPress: doDisconnect, style: { backgroundColor: dangerColor + '33', borderRadius: 8, paddingHorizontal: 12, paddingVertical: 8, borderWidth: 1, borderColor: dangerColor + '66' }, componentId: 'disconnect-btn' },
                React.createElement(Text, { testID: 'Text-16', style: { color: dangerColor, fontSize: 12, fontWeight: 'bold' } }, 'DISCONNECT')
              )
            )
          : null,
        React.createElement(View, { testID: 'View-41', style: { flexDirection: 'row', padding: 16 } },
          React.createElement(Touchable
