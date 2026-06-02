-- Migration V3: Add bitmask definitions for error and warning bits

CREATE TABLE err_bit_definitions (
    bit   SMALLINT PRIMARY KEY CHECK (bit >= 0 AND bit <= 15),
    name  TEXT     NOT NULL,
    desc  TEXT     NOT NULL DEFAULT ''
);

INSERT INTO err_bit_definitions (bit, name, desc) VALUES
(0,  'Eprom Read Error',            'Reading from Eprom defective'),
(1,  'HW Fault',                    'Critical hardware error detected'),
(2,  'RFE Input Not Present',       'Safety circuit not present (with RUN input active)'),
(3,  'CAN TimeOut Error',           'CAN TimeOut Time exceeded'),
(4,  'Feedback Signal Error',       'Bad or missing feedback signal'),
(5,  'Mains Voltage Min. Limit',    'Power voltage missing or below DC-Bus min limit'),
(6,  'Motor-Temp. Max. Limit',      'Motor temperature too high'),
(7,  'IGBT-Temp. Max. Limit',       'Output stage temperature too high'),
(8,  'Mains Voltage Max. Limit',    'Power voltage > 1.8x UN or above DC-Bus max limit'),
(9,  'Critical AC Current',         'Overcurrent or strong oscillating current detected'),
(10, 'Race Away Detected',          'Spinning without setpoint, wrong direction'),
(11, 'ECode TimeOut Error',         'Bad or missing ECode protocol'),
(12, 'Watchdog Reset',              'CPU Reset because of Watchdog detected'),
(13, 'IGBT Problem',                'AC Current Offset detection fault'),
(14, 'Internal HW Voltage Problem', 'Error because of internal Voltage problem'),
(15, 'Resistor Overload',           'Only certain motor controllers');

CREATE TABLE warn_bit_definitions (
    bit   SMALLINT PRIMARY KEY CHECK (bit >= 0 AND bit <= 15),
    name  TEXT     NOT NULL,
    desc  TEXT     NOT NULL DEFAULT ''
);

INSERT INTO warn_bit_definitions (bit, name, desc) VALUES
(0,  'Parameter Conflict Detected',  'Parameters are from different device type'),
(1,  'Special CPU Fault',            'RUN input with jitter or EMI problems'),
(2,  'RFE Input Not Present',        'Safety circuit not present (without RUN input active)'),
(3,  'Auxiliary Voltage Min. Limit', 'Auxiliary Voltage is too low'),
(4,  'Feedback Signal Problem',      'Bad or missing feedback signal (Feedback supervision deactivated)'),
(5,  'Warn. 5',                      ''),
(6,  'Motor-Temperature (>87%)',     'T-motor exceeded I-red-TM or 93% of M-Temp'),
(7,  'IGBT Temperature (>87%)',      'T-igbt > 87% vom Limit'),
(8,  'Mains Saturation Max. Limit',  'Limit of existing voltage output reached'),
(9,  'Warn. 9',                      ''),
(10, 'SpeedActual Resolution Limit', 'Resolution range of speed measurement exceeded'),
(11, 'Check ECode ID: 0x94',         'Error with ECode information at ID Register 0x94'),
(12, 'Tripzone Glitch Detected',     'Tripzone triggered unintentional'),
(13, 'ADC Sequencer Problem',        'Problem of the ADC Sequencer channels'),
(14, 'ADC Measurement Problem',      'Problem of internal ADC voltages'),
(15, 'Bleeder Resistor Load (>87%)', 'Ballast circuit > 87% overloaded');