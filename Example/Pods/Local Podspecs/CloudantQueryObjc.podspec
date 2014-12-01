license = <<EOT
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOT

Pod::Spec.new do |s|
  s.name             = "CloudantQueryObjc"
  s.version          = "1.0.0"
  s.summary          = "Implements Cloudant Query for CDTDatastore"
  s.description      = <<-DESC
                       This package adds support for a subset of Cloudant Query
                       to Cloudant Sync's iOS implementation, CDTDatastore.

                       See the README for supported features.
                       DESC
  s.homepage         = "https://github.com/cloudant/CloudantQueryObjc"
  s.license          = {:type => 'Apache', :text => license}
  s.author           = { "Cloudant, Inc." => "support@cloudant.com" }
  s.source           = { :git => "https://github.com/cloudant/CloudantQueryObjc.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes'

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.dependency 'CDTDatastore', '>= 0.7'
  s.dependency 'CocoaLumberjack', '= 2.0.0-beta4'
end
