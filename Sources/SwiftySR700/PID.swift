class PID {
    
    var Kp: Double = 0
    var Ki: Double = 0
    var Kd: Double = 0
    
    var targetTemp: Double = 0
    var error: Double = 0
    
    fileprivate var derivator: Double = 0
    fileprivate var integrator: Double = 0
    fileprivate var maxOutput: Double = 8
    fileprivate var minOutput: Double = 0
    fileprivate var maxIntegrator: Double = 8
    fileprivate var minIntegrator: Double = 0
    
    fileprivate var p: Double = 0
    fileprivate var i: Double = 0
    fileprivate var d: Double = 0

    init(p: Double, i: Double, d: Double, derivator: Double, integrator: Double, minOutput: Double, maxOutput: Double) {
        self.Kp = p
        self.Ki = i
        self.Kd = d
        self.derivator = derivator
        self.integrator = integrator
        
        minIntegrator = i > 0 ? minOutput / i : 0
        maxIntegrator = i > 0 ? maxOutput / i : 0
    }

    func update(currentTemp: Double, targetTemp: Double) -> Double {
        
        // in this implementation, ki includes the dt multiplier term,
        // and kd includes the dt divisor term.  This is typical practice in
        // industry.
        self.targetTemp = targetTemp
        error = targetTemp - currentTemp
        p = Kp * error
        
        // it is common practice to compute derivative term against PV,
        // instead of de/dt.  This is because de/dt spikes
        // when the set point changes.
        
        // PV version with no dPV/dt filter - note 'previous'-'current',
        // that's desired, how the math works out
        d = Kd * (derivator - currentTemp)
        derivator = currentTemp
        
        integrator = min(max(minIntegrator, integrator + error), maxIntegrator)
        i = integrator * Ki
        
        return min(max(minOutput, p + i + d), maxOutput)
    }
}
