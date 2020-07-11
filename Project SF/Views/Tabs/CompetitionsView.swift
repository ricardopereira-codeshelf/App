//
//  CompetitionsView.swift
//  Project SF
//
//  Created by Roman Esin on 11.07.2020.
//

import SwiftUI

struct CompetitionsView: View {

    @StateObject var healthKit = HealthKitController()

    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    Text("Competitions")
                        .navigationBarTitle("Competitions")
                    if !healthKit.success {
                        Button("Try HealthKit Auth") {
                            healthKit.authorizeHealthKit()
                        }
                    }
                    Text(healthKit.success ? "Successfully Authorized" :
                         healthKit.processBegan ? "Something went wrong" : "")
                    if healthKit.success {
                        Button("Read activity") {
                            healthKit.updateAllActivityData()
                        }
                        Button("Read steps") {
                            healthKit.update(data: .stepCount, for: Date())
                        }
                        Button("Read distance") {
                            healthKit.update(data: .distanceWalkingRunning, for: Date())
                        }
                    }
                    if healthKit.processBegan && healthKit.success {
                        HStack {
                            ActivityRings(healthKit: healthKit)
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Move: ")
                                        .bold()
                                        .foregroundColor(Color("move"))
                                    Text("\(Int(healthKit.moveCurrent))/\(Int(healthKit.moveGoal))")
                                }
                                HStack {
                                    Text("Exercise: ")
                                        .bold()
                                        .foregroundColor(Color("exercise"))
                                    Text("\(Int(healthKit.exerciseCurrent))/\(Int(healthKit.exerciseGoal))")
                                }
                                HStack {
                                    Text("Stand: ")
                                        .bold()
                                        .foregroundColor(Color("stand"))
                                    Text("\(Int(healthKit.standCurrent))/\(Int(healthKit.standGoal))")
                                }
                            }
                        }
                    }
                }
                if healthKit.processBegan && !healthKit.success {
                    ProgressView()
                }
            }

        }
        .tabItem {
            VStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 18))
                Text("Competitions")
            }
        }
        .tag(1)
    }
}

struct CompetitionsView_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionsView()
    }
}
