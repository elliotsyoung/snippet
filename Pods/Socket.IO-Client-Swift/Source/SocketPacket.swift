//
//  SocketPacket.swift
//  Socket.IO-Client-Swift
//
//  Created by Erik Little on 1/18/15.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

struct SocketPacket {
    enum PacketType: Int {
        case connect, disconnect, event, ack, error, binaryEvent, binaryAck
    }
    
    fileprivate let placeholders: Int
    
    fileprivate static let logType = "SocketPacket"

    let nsp: String
    let id: Int
    let type: PacketType
    
    var binary: [Data]
    var data: [AnyObject]
    
    var args: [AnyObject] {
        if type == .event || type == .binaryEvent && data.count != 0 {
            return Array(data.dropFirst())
        } else {
            return data
        }
    }
    
    var description: String {
        return "SocketPacket {type: \(String(type.rawValue)); data: " +
            "\(String(describing: data)); id: \(id); placeholders: \(placeholders); nsp: \(nsp)}"
    }
    
    var event: String {
        return String(describing: data[0])
    }
    
    var packetString: String {
        return createPacketString()
    }
    
    init(type: PacketType, data: [AnyObject] = [AnyObject](), id: Int = -1,
        nsp: String, placeholders: Int = 0, binary: [Data] = [Data]()) {
        self.data = data
        self.id = id
        self.nsp = nsp
        self.type = type
        self.placeholders = placeholders
        self.binary = binary
    }
    
    mutating func addData(_ data: Data) -> Bool {
        if placeholders == binary.count {
            return true
        }
        
        binary.append(data)
        
        if placeholders == binary.count {
            fillInPlaceholders()
            return true
        } else {
            return false
        }
    }
    
    fileprivate func completeMessage(_ message: String) -> String {
        let restOfMessage: String
        
        if data.count == 0 {
            return message + "[]"
        }
        
        do {
            let jsonSend = try data.toJSON()
            guard let jsonString = String(data: jsonSend as Data, encoding: String.Encoding.utf8) else { return message + "[]" }
            
            restOfMessage = jsonString
        } catch {
            DefaultSocketLogger.Logger.error("Error creating JSON object in SocketPacket.completeMessage",
                type: SocketPacket.logType)
            
            restOfMessage = "[]"
        }
        
        return message + restOfMessage
    }
    
    fileprivate func createPacketString() -> String {
        let typeString = String(type.rawValue)
        // Binary count?
        let binaryCountString = typeString + (type == .binaryEvent || type == .binaryAck ? String(binary.count) + "-" : "")
        // Namespace?
        let nspString = binaryCountString + (nsp != "/" ? nsp + "," : "")
        // Ack number?
        let idString = nspString + (id != -1 ? String(id) : "")
        
        return completeMessage(idString)
    }
    
    // Called when we have all the binary data for a packet
    // calls _fillInPlaceholders, which replaces placeholders with the
    // corresponding binary
    fileprivate mutating func fillInPlaceholders() {
        data = data.map(_fillInPlaceholders)
    }
    
    // Helper method that looks for placeholders
    // If object is a collection it will recurse
    // Returns the object if it is not a placeholder or the corresponding
    // binary data
    fileprivate func _fillInPlaceholders(_ object: AnyObject) -> AnyObject {
        switch object {
        case let dict as NSDictionary:
            if dict["_placeholder"] as? Bool ?? false {
                return binary[dict["num"] as! Int] as AnyObject
            } else {
                return dict.reduce(NSMutableDictionary(), {cur, keyValue in
                    cur[keyValue.0 as! NSCopying] = _fillInPlaceholders(keyValue.1 as AnyObject)
                    return cur
                })
            }
        case let arr as [AnyObject]:
            return arr.map(_fillInPlaceholders)
        default:
            return object
        }
    }
}

extension SocketPacket {
    fileprivate static func findType(_ binCount: Int, ack: Bool) -> PacketType {
        switch binCount {
        case 0 where !ack:
            return .event
        case 0 where ack:
            return .ack
        case _ where !ack:
            return .binaryEvent
        case _ where ack:
            return .binaryAck
        default:
            return .error
        }
    }
    
    static func packetFromEmit(_ items: [AnyObject], id: Int, nsp: String, ack: Bool) -> SocketPacket {
        let (parsedData, binary) = deconstructData(items)
        let packet = SocketPacket(type: findType(binary.count, ack: ack), data: parsedData,
            id: id, nsp: nsp, binary: binary)
        
        return packet
    }
}

private extension SocketPacket {
    // Recursive function that looks for NSData in collections
    static func shred(_ data: AnyObject, binary: inout [Data]) -> AnyObject {
        let placeholder = ["_placeholder": true, "num": binary.count] as [String : Any]
        
        switch data {
        case let bin as Data:
            binary.append(bin)
            return placeholder as AnyObject
        case let arr as [AnyObject]:
            return arr.map({shred($0, binary: &binary)})
        case let dict as NSDictionary:
            return dict.reduce(NSMutableDictionary(), {cur, keyValue in
                cur[keyValue.0 as! NSCopying] = shred(keyValue.1 as AnyObject, binary: &binary)
                return cur
            })
        default:
            return data
        }
    }
    
    // Removes binary data from emit data
    // Returns a type containing the de-binaryed data and the binary
    static func deconstructData(_ data: [AnyObject]) -> ([AnyObject], [Data]) {
        var binary = [Data]()
        
        return (data.map({shred($0, binary: &binary)}), binary)
    }
}
