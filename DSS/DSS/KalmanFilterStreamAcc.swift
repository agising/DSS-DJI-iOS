//
//  KalmanFilter
//
//  Created by Kristoffer Bergman and  Andreas Gising.
//  Adopted from 2017 Hypercube. All rights reserved.
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//    THE SOFTWARE.

import Foundation
import MapKit
import Surge

open class GPSKalmanFilterAcc
{
    // MaxTimeLost, Controls resetNeeded fcn
    var maxTimeLost: Double
    var timeInterval: Double

    // The dimension of the state and measurements.
    private let n_states = 9
    private let n_measurements = 3

    // State vector (north, east, alt, v_n, v_e, v_alt, a_n, a_e, a_alt)
    private var xk:Matrix<Double>

    // State covariance matrix
    private var Pk:Matrix<Double>

    // State transition matrix
    private var Fk:Matrix<Double>

    // Process noise covariance matrix
    private var Qk:Matrix<Double>

    // Observation model matrix
    private var H:Matrix<Double>
    private var I:Matrix<Double>

    // Observation Noise Covariance Matrix
    private var R:Matrix<Double>

    // Measurements
    private var zk:Matrix<Double>

    // Parameters for Process noise covariance matrix
    private let sigmaNE = 4.0 // 0.0625 //0.9
    private let sigmaAlt = 0.0625
    // ACC filter, cyclist returning, steady state
    // Parameters for measurement noise convariance matrix
    private var rValueNE  = 5000.0 // Update stepper too! 0.09 //25.0 // 0.09
    private var rValueAlt = 0.05

    // Parameters for initialization of Covariance Matrix
    private let sigmaNEInit = 5.0
    private let sigmaAltInit = 5.0
    private let sigmaVelNEInit = 0.5
    private let sigmaVelAltInit = 0.5
    private let sigmaAccNEInit = 0.2
    private let sigmaAccAltInit = 0.2

    // Origin state location (for transform from lat/lon to Euclidean coordinate system)
    private var originLocation = CLLocation()

    //
    private var previousLocation = CLLocation()

    //
    private var previousMeasureTime = CACurrentMediaTime()

    // Initialization of Kalman Algorithm Constructor
    // ==============================================
    // - parameters:
    //   - initialLocation: this is CLLocation object which represent initial location
    //                      at the moment when algorithm start
    //   - timeInterval: Specification of how fast the filter shall be executed
    //   - maxTimeLost: Time that is used to indicate if filter needs a reset
    public init(initialLocation: CLLocation, timeInterval: Double, maxTimeLost: Double=10)
    {
        self.timeInterval = timeInterval

        self.maxTimeLost = maxTimeLost
        self.xk = Matrix<Double>(rows: self.n_states, columns: 1, repeatedValue: 0.0)
        self.Pk = Matrix<Double>(rows: self.n_states, columns: self.n_states, repeatedValue: 0.0)
        self.Fk = Matrix<Double>(rows: self.n_states, columns: self.n_states, repeatedValue: 0.0)
        self.Qk = Matrix<Double>(rows: self.n_states, columns: self.n_states, repeatedValue: 0.0)
        self.H = Matrix<Double>(rows: self.n_measurements, columns: self.n_states, repeatedValue: 0.0)
        self.I = Matrix<Double>(rows: self.n_states, columns: self.n_states, repeatedValue: 0.0)
        self.R = Matrix<Double>(rows: self.n_measurements, columns: self.n_measurements, repeatedValue: 0.0)
        self.zk = Matrix<Double>(rows: self.n_measurements, columns: 1, repeatedValue: 0.0)

        // Set Non-time dependent matrices
        self.R = Matrix<Double>([[self.rValueNE, 0, 0],[0, self.rValueNE, 0],[0, 0, self.rValueAlt]])
        self.H = Matrix<Double>([[1,0,0,0,0,0,0,0,0],[0,1,0,0,0,0,0,0,0],[0,0,1,0,0,0,0,0,0]])
        self.I = self.getIdentityMatrix(dim: self.n_states)
        // Update time-dependent model matrices

        self.initModelMatrices()
        self.resetFilter(initialLocation: initialLocation)

        print("Filter is initialized")
    }

    func copy(with zone: NSZone? = nil)->Any{
        let copy = GPSKalmanFilterAcc(initialLocation: originLocation, timeInterval: timeInterval)

        copy.maxTimeLost = maxTimeLost
        copy.timeInterval = timeInterval
        copy.xk = xk
        copy.Pk = Pk
        copy.Fk = Fk
        copy.Qk = Qk
        copy.H = H
        copy.I = I
        copy.R = R
        copy.zk = zk
        copy.rValueNE = rValueNE
        copy.rValueAlt = rValueAlt
        copy.originLocation = originLocation
        copy.previousLocation = previousLocation
        copy.previousMeasureTime = previousMeasureTime
        return copy
    }


    // Init model matrices that depends on the frequency of the filter
    open func initModelMatrices()
    {
        // Compute state transition matrix based on time interval
        let t2half = pow(timeInterval,2)/2
        self.Fk = Matrix<Double>([[1,0,0,timeInterval,0,0, t2half, 0, 0],
                                  [0,1,0,0,timeInterval,0, 0, t2half, 0],
                                  [0,0,1,0,0,timeInterval, 0, 0, t2half],
                                  [0,0,0,1,0,0, timeInterval, 0, 0],
                                  [0,0,0,0,1,0, 0, timeInterval, 0],
                                  [0,0,0,0,0,1, 0, 0, timeInterval],
                                 [0,0,0,0,0,0,1,0,0],
                                 [0,0,0,0,0,0,0,1,0],
                                 [0,0,0,0,0,0,0,0,1]])

        // Parts of Acceleration Noise Magnitude Matrix
        let dt4 = Double(pow(Double(timeInterval), Double(4)))
        let dt3 = Double(pow(Double(timeInterval), Double(3)))
        let dt2 = Double(pow(Double(timeInterval), Double(2)))

        let p1NE = self.sigmaNE * dt4/4
        let p2NE = self.sigmaNE * dt3/2
        let p3NE = self.sigmaNE * dt2
        let p4NE = self.sigmaNE * dt2/2
        let p5NE = self.sigmaNE * timeInterval

        let p1Alt = self.sigmaAlt * dt4/4
        let p2Alt = self.sigmaAlt * dt3/2
        let p3Alt = self.sigmaAlt * dt2
        let p4Alt = self.sigmaAlt * dt2/2
        let p5Alt = self.sigmaAlt * timeInterval
        // Calculate and set Acceleration Noise Magnitude Matrix based on new timeInterval and sigma values
        self.Qk = Matrix<Double>([[p1NE,0.0,0.0,p2NE,0.0,0.0,p4NE, 0.0, 0.0],
                                  [0.0,p1NE,0.0,0.0,p2NE,0.0, 0.0, p4NE, 0.0],
                                  [0.0,0.0,p1Alt,0.0,0.0,p2Alt, 0.0,0.0, p4Alt],
                                  [p2NE,0.0,0.0,p3NE,0.0,0.0, p5NE, 0.0, 0.0],
                                  [0.0,p2NE,0.0,0.0,p3NE,0.0, 0.0, p5NE, 0.0],
                                  [0.0,0.0,p2Alt,0.0,0.0,p3Alt, 0.0, 0.0, p5Alt],
                                  [p4NE, 0.0, 0.0, p5NE, 0.0, 0.0, self.sigmaNE, 0.0, 0.0],
                                  [0.0, p4NE, 0.0, 0.0, p5NE, 0.0, 0.0, self.sigmaNE, 0.0],
                                  [0.0, 0.0, p4Alt, 0.0, 0.0, p5Alt, 0.0, 0.0, self.sigmaAlt]])
    }

    // Reset Kalman Filter
    private func resetFilter(initialLocation: CLLocation)
    {
        // Set timestamp for start of measuring
        self.previousMeasureTime = CACurrentMediaTime()

        // Set initial location
        self.previousLocation = initialLocation
        self.originLocation = initialLocation
        // Set initial state (assume starting at the origin)
        self.xk = Matrix<Double>([[0.0],[0.0],[initialLocation.altitude],[0.0],[0.0],[0.0], [0.0], [0.0], [0.0]])
        // Initialize Covariance matrix
        self.Pk = Matrix<Double>([[sigmaNEInit,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0],
                                  [0.0,sigmaNEInit,0.0,0.0,0.0,0.0,0.0,0.0,0.0],
                                  [0.0,0.0,sigmaAltInit,0.0,0.0,0.0,0.0,0.0,0.0],
                                  [0.0,0.0,0.0,sigmaVelNEInit,0.0,0.0,0.0,0.0,0.0],
                                  [0.0,0.0,0.0,0.0,sigmaVelNEInit,0.0,0.0,0.0,0.0],
                                  [0.0,0.0,0.0,0.0,0.0,sigmaVelAltInit,0.0,0.0,0.0],
                                  [0.0,0.0,0.0,0.0,0.0,0.0, sigmaAccNEInit,0.0,0.0],
                                  [0.0,0.0,0.0,0.0,0.0,0.0,0.0,sigmaAccNEInit,0.0],
                                  [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,sigmaAccAltInit],
                                 ])
    }

    // Change rNE and/or rAlt in flight
    open func tuneR(rNE: Double? = nil, rAlt: Double? = nil){
        if rNE != nil{
            rValueNE = rNE!
        }
        if rAlt != nil{
            rValueAlt = rAlt!
        }
        self.R = Matrix<Double>([[rValueNE, 0, 0],[0, rValueNE, 0],[0, 0, rValueAlt]])
    }

    // Reset filter using initial state and covariance
    open func reset_with_covariance(x0: Matrix<Double>, P0: Matrix<Double>)
    {
        //TODO check that dimensions are correct
        self.xk = x0
        self.Pk = P0
    }
    // Reset filter from a given start position
    open func reset(newStartLocation: CLLocation)
    {
        self.resetFilter(initialLocation: newStartLocation)
    }

    // Reset if too much time since last measurement
    open func resetNeeded() -> Bool {
        if CACurrentMediaTime() - self.previousMeasureTime > self.maxTimeLost{
            return true
        }
        return false
    }
    open func ll_to_ne(llInput: CLLocation) -> (Double, Double)
    {
        let north = (llInput.coordinate.latitude-self.originLocation.coordinate.latitude) * 1852 * 60
        let east =  (llInput.coordinate.longitude-self.originLocation.coordinate.longitude) * 1852 * 60 * cos(self.originLocation.coordinate.latitude*Double.pi/180)
        return (north, east)
    }
    open func ne_to_ll(north: Double, east: Double) -> (Double, Double)
    {
        let lat = self.originLocation.coordinate.latitude + north/(1852*60)
        let lon = self.originLocation.coordinate.longitude + east/(1852*60*cos(self.originLocation.coordinate.latitude*Double.pi/180))
        return (lat, lon)
    }
    // Prediction step
    open func predict()
    {
        self.xk = self.Fk * self.xk
        self.Pk = self.Fk * self.Pk * Surge.transpose(self.Fk) + self.Qk
        //print("Kalman Predicted N: ", self.xk[0,0], "time: ", CACurrentMediaTime())

    }
    // Update step
    open func update(currentLocation: CLLocation)
    {
        
        if resetNeeded(){
            self.reset(newStartLocation: currentLocation)
            return
        }
        
        //print("Prior_ update: PosE: ", self.xk[1,0], " VelE: ", self.xk[4,0], "AccE: ", self.xk[7,0])
        self.previousMeasureTime = CACurrentMediaTime()
        let (north_m, east_m) = self.ll_to_ne(llInput: currentLocation)
        self.zk = Matrix<Double>([[north_m], [east_m], [currentLocation.altitude]])
        let y = self.zk - self.H * self.xk
        let S = self.R + self.H * self.Pk * Surge.transpose(self.H)
        let K = self.Pk * Surge.transpose(self.H) * Surge.inv(S)

        //Update state
        self.xk = self.xk + K*y
        //Update state covariance matrix
        self.Pk = (self.I - K  * self.H) * self.Pk * Surge.transpose(self.I - K * self.H) + K * self.R * Surge.transpose(K)
        //print("Kalman Upated       N: ", self.xk[0,0], "time: ", CACurrentMediaTime())
        //print("Filter update: PosE: ", self.xk[1,0], " VelE: ", self.xk[4,0], "AccE: ", self.xk[7,0], " MeasurementEast: ", east_m)
        //print("")

    }
    open func getLlaState() -> CLLocation
    {
        let (lat, lon) = self.ne_to_ll(north: self.xk[0,0], east: self.xk[1,0])
        let verticalAccuracy = sqrt(self.Pk[2,2])
        let horizontalAccuracy = sqrt(self.Pk[0,0] + self.Pk[1,1])
        let llaState = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat,longitude: lon), altitude: self.xk[2,0], horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, timestamp: Date())
        return llaState
    }

    open func getVelocities()->(Double, Double, Double){
        let velNorth = self.xk[3,0]
        let velEast = self.xk[4,0]
        let velAlt = self.xk[5,0]
        return(velNorth,velEast, velAlt)
    }

    func getIdentityMatrix(dim:Int) -> Matrix<Double>
    {
        var identityMatrix = Matrix<Double>(rows: dim, columns: dim, repeatedValue: 0.0)
        for i in 0..<dim {
            for j in 0..<dim{
                if i == j
                {
                    identityMatrix[i,j] = 1.0
                }
            }
        }
        return identityMatrix
    }
}
