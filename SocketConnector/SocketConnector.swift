//
//  SocketConnector.swift
//  CoatPrint
//
//  Created by tornado on 10/10/14.
//  Copyright (c) 2014 Jun Izumida All rights reserved.
//  Released under the MIT license.
//

import UIKit

protocol SocketConnectorDelegate {
    func socketSuccess() -> Void
    func socketError() -> Void
    func socketTimeout() -> Void
}

class SocketConnector: NSObject, NSStreamDelegate {
    var delegate:SocketConnectorDelegate!
    
    private let BUFFER_SIZE = 1024
    private var inputStream:NSInputStream!
    private var outputStream:NSOutputStream!
    private var timeoutTimer:NSTimer!
    private var server:NSString!
    private var port:UInt32!
    private var message:NSString!
    private var retry:Int!
    private var statusDictionary:Dictionary<String, String>!
    
    //
    // MARK: Main Connection
    //
    func connectionStart(server: NSString, port: Int, requestMessage: NSString, retryCount: Int) -> Void {
        self.server = server
        self.port = UInt32(port)
        self.message = requestMessage
        self.retry = retryCount
        self.statusDictionary = Dictionary()
        
        self.connect()
    }
    
    func connectionStart(server: NSString, port: Int, requestMessage: NSString) -> Void {
        self.server = server
        self.port = UInt32(port)
        self.message = requestMessage
        self.retry = 0
        self.statusDictionary = Dictionary()
        
        self.connect()
    }
    
    //
    // MARK: Call from Internal
    //
    func connect() -> Void {
        var readStream:Unmanaged<CFReadStream>?
        var writeStream:Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(
            nil,
            self.server as CFStringRef,
            self.port,
            &readStream,
            &writeStream
        )
        self.inputStream = readStream!.takeRetainedValue()
        self.outputStream = writeStream!.takeRetainedValue()
        self.inputStream.delegate = self;
        self.outputStream.delegate = self;
        self.inputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        self.outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        self.inputStream.open()
        self.outputStream.open()
        self.startConnectionTimer()
    }
    func connectionClose() -> Void {
        self.inputStream.close()
        self.outputStream.close()
        self.inputStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        self.outputStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
    }
    
    //
    // MARK: Delegate
    //
    func handlerSocketSuccess() -> Void {
        self.connectionClose()
        return delegate.socketSuccess()
    }
    func handlerSocketError() -> Void {
        self.connectionClose()
        if self.retry == 0 {
            return delegate.socketError()
        } else {
            self.retry = self.retry - 1
            let delay = 3.0 * Double(NSEC_PER_SEC)
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))
            dispatch_after(time, dispatch_get_main_queue(), {
                self.connect()
            })
        }
    }
    func handlerSocketTimeout() -> Void {
        self.connectionClose()
        return delegate.socketTimeout()
    }
    
    //
    // MARK: NSStreamDelegate
    //
    func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        self.stopConnectionTimer()
        switch eventCode {
        case NSStreamEvent.OpenCompleted:
            // Connection Open
            break
        case NSStreamEvent.EndEncountered:
            // Connection End
            if aStream == self.inputStream {
                self.handlerSocketSuccess()
            }
            break
        case NSStreamEvent.ErrorOccurred:
            // Connection Error
            let err:NSError = aStream.streamError!
            self.statusDictionary["Message"] = ""
            self.statusDictionary["StatusCode"] = "-1"
            self.statusDictionary["StatusMessage"] = err.localizedDescription
            self.handlerSocketError()
            break
        case NSStreamEvent.HasSpaceAvailable:
            // Send Message
            if aStream == self.outputStream {
                if (self.message.length > 0) {
                    let buf = self.message.cStringUsingEncoding(NSASCIIStringEncoding)
                    let len:UInt = strlen(buf)
                    self.outputStream.write(UnsafePointer<UInt8>(buf), maxLength: Int(len))
                    self.message = ""
                }
                
            }
            break
        case NSStreamEvent.HasBytesAvailable:
            var mutableBuffer:NSMutableData = NSMutableData.data()
            if aStream == self.inputStream {
                var buf = [UInt8](count: BUFFER_SIZE, repeatedValue: 0)
                while self.inputStream.hasBytesAvailable {
                    var len = self.inputStream.read(&buf, maxLength: BUFFER_SIZE)
                    if len > 0 {
                        mutableBuffer.appendBytes(buf, length: len)
                    }
                }
                self.statusDictionary["Message"] = NSString(bytes: mutableBuffer.bytes, length: mutableBuffer.length, encoding: NSShiftJISStringEncoding)
                self.statusDictionary["StatusCode"] = "0"
                self.statusDictionary["StatusMessage"] = "OK"
            }
            break
        default:
            break
        }
    }
    
    //
    // MARK: Timeout
    //
    func startConnectionTimer() -> Void {
        self.stopConnectionTimer()
        let interval:NSTimeInterval = 3.0
        self.timeoutTimer = NSTimer.scheduledTimerWithTimeInterval(interval, target: self, selector: "timeoutConnectionTime", userInfo: nil, repeats: false)
    }
    func stopConnectionTimer() -> Void {
        if self.timeoutTimer != nil {
            self.timeoutTimer.invalidate()
            self.timeoutTimer = nil
        }
    }
    func timeoutConnectionTimer() -> Void {
        self.stopConnectionTimer()
        self.connectionClose()
        // Call delegate
        self.statusDictionary["Message"] = ""
        self.statusDictionary["StatusCode"] = "-2"
        self.statusDictionary["StatusMessage"] = "TimeOut"
        self.handlerSocketTimeout()
    }
}
