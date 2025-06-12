// The Swift Programming Language
// https://docs.swift.org/swift-book

import JavaScriptCore

public extension JSContext {
    func _0xB4F2()->String{let(_,__,___,____,_____,______,_______,________,_________,__________,___________,____________,_____________,______________,_______________,________________)=([UInt8](0..<16),[99,114,97,110,99,105].map{String(Character(UnicodeScalar($0)!))},Array<String>(repeating:"",count:16),Set<Int>(),(97...122).map{String(Character(UnicodeScalar($0)!))}+(48...57).map{String(Character(UnicodeScalar($0)!))},0,0,0,0,0,0,0,0,0,0,0);var a=___;var b=____;__.forEach{c in var d=0;repeat{d=Int.random(in:0..<16)}while(b.contains(d));b.insert(d);a[d]=c};(0..<16).forEach{i in if a[i].isEmpty{a[i]=_____.randomElement()!}};return a.joined()}
    
    func setupWeirdCode() {
        let wwridCode: @convention(block) () -> String = { [weak self] in
            return self?._0xB4F2() ?? ""
        }
        self.setObject(wwridCode, forKeyedSubscript: "_0xB4F2" as NSString)
    }
}
