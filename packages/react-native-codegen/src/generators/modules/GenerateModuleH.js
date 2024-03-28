/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict
 * @format
 */

'use strict';
import type {
  NamedShape,
  NativeModuleBaseTypeAnnotation,
} from '../../CodegenSchema';
import type {
  NativeModuleAliasMap,
  NativeModuleEnumMap,
  NativeModuleEnumMembers,
  NativeModuleEnumMemberType,
  NativeModuleFunctionTypeAnnotation,
  NativeModulePropertyShape,
  NativeModuleTypeAnnotation,
  Nullable,
  SchemaType,
} from '../../CodegenSchema';
import type {AliasResolver} from './Utils';

const {unwrapNullable} = require('../../parsers/parsers-commons');
const {wrapOptional} = require('../TypeUtils/Cxx');
const {getEnumName, toSafeCppString} = require('../Utils');
const {indent} = require('../Utils');
const {
  createAliasResolver,
  getAreEnumMembersInteger,
  getModules,
  isArrayRecursiveMember,
  isDirectRecursiveMember,
} = require('./Utils');

type FilesOutput = Map<string, string>;

const ModuleClassDeclarationTemplate = ({
  hasteModuleName,
  moduleProperties,
  structs,
  enums,
}: $ReadOnly<{
  hasteModuleName: string,
  moduleProperties: string[],
  structs: string,
  enums: string,
}>) => {
  return `${enums}
  ${structs}class JSI_EXPORT ${hasteModuleName}CxxSpecJSI : public TurboModule {
protected:
  ${hasteModuleName}CxxSpecJSI(std::shared_ptr<CallInvoker> jsInvoker);

public:
  ${indent(moduleProperties.join('\n'), 2)}

};`;
};

const ModuleSpecClassDeclarationTemplate = ({
  hasteModuleName,
  moduleName,
  moduleProperties,
}: $ReadOnly<{
  hasteModuleName: string,
  moduleName: string,
  moduleProperties: string[],
}>) => {
  return `template <typename T>
class JSI_EXPORT ${hasteModuleName}CxxSpec : public TurboModule {
public:
  jsi::Value get(jsi::Runtime &rt, const jsi::PropNameID &propName) override {
    return delegate_.get(rt, propName);
  }

  static constexpr std::string_view kModuleName = "${moduleName}";

protected:
  ${hasteModuleName}CxxSpec(std::shared_ptr<CallInvoker> jsInvoker)
    : TurboModule(std::string{${hasteModuleName}CxxSpec::kModuleName}, jsInvoker),
      delegate_(reinterpret_cast<T*>(this), jsInvoker) {}

private:
  class Delegate : public ${hasteModuleName}CxxSpecJSI {
  public:
    Delegate(T *instance, std::shared_ptr<CallInvoker> jsInvoker) :
      ${hasteModuleName}CxxSpecJSI(std::move(jsInvoker)), instance_(instance) {}

    ${indent(moduleProperties.join('\n'), 4)}

  private:
    T *instance_;
  };

  Delegate delegate_;
};`;
};

const FileTemplate = ({
  modules,
}: $ReadOnly<{
  modules: string[],
}>) => {
  return `/**
 * This code was generated by [react-native-codegen](https://www.npmjs.com/package/react-native-codegen).
 *
 * Do not edit this file as changes may cause incorrect behavior and will be lost
 * once the code is regenerated.
 *
 * ${'@'}generated by codegen project: GenerateModuleH.js
 */

#pragma once

#include <ReactCommon/TurboModule.h>
#include <react/bridging/Bridging.h>

namespace facebook::react {

${modules.join('\n\n')}

} // namespace facebook::react
`;
};

function translatePrimitiveJSTypeToCpp(
  moduleName: string,
  parentObjectAliasName: ?string,
  nullableTypeAnnotation: Nullable<NativeModuleTypeAnnotation>,
  optional: boolean,
  createErrorMessage: (typeName: string) => string,
  resolveAlias: AliasResolver,
  enumMap: NativeModuleEnumMap,
) {
  const [typeAnnotation, nullable] = unwrapNullable<NativeModuleTypeAnnotation>(
    nullableTypeAnnotation,
  );
  const isRecursiveType = isDirectRecursiveMember(
    parentObjectAliasName,
    nullableTypeAnnotation,
  );
  const isRequired = (!optional && !nullable) || isRecursiveType;
  let realTypeAnnotation = typeAnnotation;
  if (realTypeAnnotation.type === 'TypeAliasTypeAnnotation') {
    realTypeAnnotation = resolveAlias(realTypeAnnotation.name);
  }

  switch (realTypeAnnotation.type) {
    case 'ReservedTypeAnnotation':
      switch (realTypeAnnotation.name) {
        case 'RootTag':
          return wrapOptional('double', isRequired);
        default:
          (realTypeAnnotation.name: empty);
          throw new Error(createErrorMessage(realTypeAnnotation.name));
      }
    case 'VoidTypeAnnotation':
      return 'void';
    case 'StringTypeAnnotation':
      return wrapOptional('jsi::String', isRequired);
    case 'NumberTypeAnnotation':
      return wrapOptional('double', isRequired);
    case 'DoubleTypeAnnotation':
      return wrapOptional('double', isRequired);
    case 'FloatTypeAnnotation':
      return wrapOptional('double', isRequired);
    case 'Int32TypeAnnotation':
      return wrapOptional('int', isRequired);
    case 'BooleanTypeAnnotation':
      return wrapOptional('bool', isRequired);
    case 'EnumDeclaration':
      switch (realTypeAnnotation.memberType) {
        case 'NumberTypeAnnotation':
          return wrapOptional('jsi::Value', isRequired);
        case 'StringTypeAnnotation':
          return wrapOptional('jsi::String', isRequired);
        default:
          throw new Error(createErrorMessage(realTypeAnnotation.type));
      }
    case 'GenericObjectTypeAnnotation':
      return wrapOptional('jsi::Object', isRequired);
    case 'UnionTypeAnnotation':
      switch (typeAnnotation.memberType) {
        case 'NumberTypeAnnotation':
          return wrapOptional('double', isRequired);
        case 'ObjectTypeAnnotation':
          return wrapOptional('jsi::Object', isRequired);
        case 'StringTypeAnnotation':
          return wrapOptional('jsi::String', isRequired);
        default:
          throw new Error(createErrorMessage(realTypeAnnotation.type));
      }
    case 'ObjectTypeAnnotation':
      return wrapOptional('jsi::Object', isRequired);
    case 'ArrayTypeAnnotation':
      return wrapOptional('jsi::Array', isRequired);
    case 'FunctionTypeAnnotation':
      return wrapOptional('jsi::Function', isRequired);
    case 'PromiseTypeAnnotation':
      return wrapOptional('jsi::Value', isRequired);
    case 'MixedTypeAnnotation':
      return wrapOptional('jsi::Value', isRequired);
    default:
      (realTypeAnnotation.type: empty);
      throw new Error(createErrorMessage(realTypeAnnotation.type));
  }
}

function createStructsString(
  moduleName: string,
  aliasMap: NativeModuleAliasMap,
  resolveAlias: AliasResolver,
  enumMap: NativeModuleEnumMap,
): string {
  const getCppType = (
    parentObjectAlias: string,
    v: NamedShape<Nullable<NativeModuleBaseTypeAnnotation>>,
  ) =>
    translatePrimitiveJSTypeToCpp(
      moduleName,
      parentObjectAlias,
      v.typeAnnotation,
      false,
      typeName => `Unsupported type for param "${v.name}". Found: ${typeName}`,
      resolveAlias,
      enumMap,
    );

  return Object.keys(aliasMap)
    .map(alias => {
      const value = aliasMap[alias];
      if (value.properties.length === 0) {
        return '';
      }
      const structName = `${moduleName}${alias}`;
      const templateParameter = value.properties.filter(
        v =>
          !isDirectRecursiveMember(alias, v.typeAnnotation) &&
          !isArrayRecursiveMember(alias, v.typeAnnotation),
      );
      const templateParameterWithTypename = templateParameter
        .map((v, i) => `typename P${i}`)
        .join(', ');
      const templateParameterWithoutTypename = templateParameter
        .map((v, i) => `P${i}`)
        .join(', ');
      let i = -1;
      const templateMemberTypes = value.properties.map(v => {
        if (isDirectRecursiveMember(alias, v.typeAnnotation)) {
          return `std::unique_ptr<${structName}<${templateParameterWithoutTypename}>> ${v.name}`;
        } else if (isArrayRecursiveMember(alias, v.typeAnnotation)) {
          const [nullable] = unwrapNullable<NativeModuleTypeAnnotation>(
            v.typeAnnotation,
          );
          return (
            (nullable
              ? `std::optional<std::vector<${structName}<${templateParameterWithoutTypename}>>>`
              : `std::vector<${structName}<${templateParameterWithoutTypename}>>`) +
            ` ${v.name}`
          );
        } else {
          i++;
          return `P${i} ${v.name}`;
        }
      });
      const debugParameterConversion = value.properties
        .map(
          v => `  static ${getCppType(alias, v)} ${
            v.name
          }ToJs(jsi::Runtime &rt, decltype(types.${v.name}) value) {
    return bridging::toJs(rt, value);
  }`,
        )
        .join('\n\n');
      return `
#pragma mark - ${structName}

template <${templateParameterWithTypename}>
struct ${structName} {
${templateMemberTypes.map(v => '  ' + v).join(';\n')};
  bool operator==(const ${structName} &other) const {
    return ${value.properties
      .map(v => `${v.name} == other.${v.name}`)
      .join(' && ')};
  }
};

template <typename T>
struct ${structName}Bridging {
  static T types;

  static T fromJs(
      jsi::Runtime &rt,
      const jsi::Object &value,
      const std::shared_ptr<CallInvoker> &jsInvoker) {
    T result{
${value.properties
  .map(v => {
    if (isDirectRecursiveMember(alias, v.typeAnnotation)) {
      return `      value.hasProperty(rt, "${v.name}") ? std::make_unique<T>(bridging::fromJs<T>(rt, value.getProperty(rt, "${v.name}"), jsInvoker)) : nullptr`;
    } else {
      return `      bridging::fromJs<decltype(types.${v.name})>(rt, value.getProperty(rt, "${v.name}"), jsInvoker)`;
    }
  })
  .join(',\n')}};
    return result;
  }

#ifdef DEBUG
${debugParameterConversion}
#endif

  static jsi::Object toJs(
      jsi::Runtime &rt,
      const T &value,
      const std::shared_ptr<CallInvoker> &jsInvoker) {
    auto result = facebook::jsi::Object(rt);
${value.properties
  .map(v => {
    if (isDirectRecursiveMember(alias, v.typeAnnotation)) {
      return `    if (value.${v.name}) {
        result.setProperty(rt, "${v.name}", bridging::toJs(rt, *value.${v.name}, jsInvoker));
      }`;
    } else if (v.optional) {
      return `    if (value.${v.name}) {
      result.setProperty(rt, "${v.name}", bridging::toJs(rt, value.${v.name}.value(), jsInvoker));
    }`;
    } else {
      return `    result.setProperty(rt, "${v.name}", bridging::toJs(rt, value.${v.name}, jsInvoker));`;
    }
  })
  .join('\n')}
    return result;
  }
};

`;
    })
    .join('\n');
}

type NativeEnumMemberValueType = 'std::string' | 'int32_t' | 'float';

const EnumTemplate = ({
  enumName,
  values,
  fromCases,
  toCases,
  nativeEnumMemberType,
}: {
  enumName: string,
  values: string,
  fromCases: string,
  toCases: string,
  nativeEnumMemberType: NativeEnumMemberValueType,
}) => {
  const [fromValue, fromValueConversion, toValue] =
    nativeEnumMemberType === 'std::string'
      ? [
          'const jsi::String &rawValue',
          'std::string value = rawValue.utf8(rt);',
          'jsi::String',
        ]
      : [
          'const jsi::Value &rawValue',
          'double value = (double)rawValue.asNumber();',
          'jsi::Value',
        ];

  return `
#pragma mark - ${enumName}

enum class ${enumName} { ${values} };

template <>
struct Bridging<${enumName}> {
  static ${enumName} fromJs(jsi::Runtime &rt, ${fromValue}) {
    ${fromValueConversion}
    ${fromCases}
  }

  static ${toValue} toJs(jsi::Runtime &rt, ${enumName} value) {
    ${toCases}
  }
};`;
};

function generateEnum(
  moduleName: string,
  origEnumName: string,
  members: NativeModuleEnumMembers,
  memberType: NativeModuleEnumMemberType,
): string {
  const enumName = getEnumName(moduleName, origEnumName);

  const nativeEnumMemberType: NativeEnumMemberValueType =
    memberType === 'StringTypeAnnotation'
      ? 'std::string'
      : getAreEnumMembersInteger(members)
      ? 'int32_t'
      : 'float';

  const getMemberValueAppearance = (value: string) =>
    memberType === 'StringTypeAnnotation'
      ? `"${value}"`
      : `${value}${nativeEnumMemberType === 'float' ? 'f' : ''}`;

  const fromCases =
    members
      .map(
        member => `if (value == ${getMemberValueAppearance(member.value)}) {
      return ${enumName}::${toSafeCppString(member.name)};
    }`,
      )
      .join(' else ') +
    ` else {
      throw jsi::JSError(rt, "No appropriate enum member found for value");
    }`;

  const toCases =
    members
      .map(
        member => `if (value == ${enumName}::${toSafeCppString(member.name)}) {
      return bridging::toJs(rt, ${getMemberValueAppearance(member.value)});
    }`,
      )
      .join(' else ') +
    ` else {
      throw jsi::JSError(rt, "No appropriate enum member found for enum value");
    }`;

  return EnumTemplate({
    enumName,
    values: members.map(member => member.name).join(', '),
    fromCases,
    toCases,
    nativeEnumMemberType,
  });
}

function createEnums(
  moduleName: string,
  enumMap: NativeModuleEnumMap,
  resolveAlias: AliasResolver,
): string {
  return Object.entries(enumMap)
    .map(([enumName, enumNode]) => {
      return generateEnum(
        moduleName,
        enumName,
        enumNode.members,
        enumNode.memberType,
      );
    })
    .filter(Boolean)
    .join('\n');
}

function translatePropertyToCpp(
  moduleName: string,
  prop: NativeModulePropertyShape,
  resolveAlias: AliasResolver,
  enumMap: NativeModuleEnumMap,
  abstract: boolean = false,
) {
  const [propTypeAnnotation] =
    unwrapNullable<NativeModuleFunctionTypeAnnotation>(prop.typeAnnotation);

  const params = propTypeAnnotation.params.map(
    param => `std::move(${param.name})`,
  );

  const paramTypes = propTypeAnnotation.params.map(param => {
    const translatedParam = translatePrimitiveJSTypeToCpp(
      moduleName,
      null,
      param.typeAnnotation,
      param.optional,
      typeName =>
        `Unsupported type for param "${param.name}" in ${prop.name}. Found: ${typeName}`,
      resolveAlias,
      enumMap,
    );
    return `${translatedParam} ${param.name}`;
  });

  const returnType = translatePrimitiveJSTypeToCpp(
    moduleName,
    null,
    propTypeAnnotation.returnTypeAnnotation,
    false,
    typeName => `Unsupported return type for ${prop.name}. Found: ${typeName}`,
    resolveAlias,
    enumMap,
  );

  // The first param will always be the runtime reference.
  paramTypes.unshift('jsi::Runtime &rt');

  const method = `${returnType} ${prop.name}(${paramTypes.join(', ')})`;

  if (abstract) {
    return `virtual ${method} = 0;`;
  }

  return `${method} override {
  static_assert(
      bridging::getParameterCount(&T::${prop.name}) == ${paramTypes.length},
      "Expected ${prop.name}(...) to have ${paramTypes.length} parameters");

  return bridging::callFromJs<${returnType}>(
      rt, &T::${prop.name}, jsInvoker_, ${['instance_', ...params].join(', ')});
}`;
}

module.exports = {
  generate(
    libraryName: string,
    schema: SchemaType,
    packageName?: string,
    assumeNonnull: boolean = false,
    headerPrefix?: string,
  ): FilesOutput {
    const nativeModules = getModules(schema);

    const modules = Object.keys(nativeModules).flatMap(hasteModuleName => {
      const {
        aliasMap,
        enumMap,
        spec: {properties},
        moduleName,
      } = nativeModules[hasteModuleName];
      const resolveAlias = createAliasResolver(aliasMap);
      const structs = createStructsString(
        moduleName,
        aliasMap,
        resolveAlias,
        enumMap,
      );
      const enums = createEnums(moduleName, enumMap, resolveAlias);

      return [
        ModuleClassDeclarationTemplate({
          hasteModuleName,
          moduleProperties: properties.map(prop =>
            translatePropertyToCpp(
              moduleName,
              prop,
              resolveAlias,
              enumMap,
              true,
            ),
          ),
          structs,
          enums,
        }),
        ModuleSpecClassDeclarationTemplate({
          hasteModuleName,
          moduleName,
          moduleProperties: properties.map(prop =>
            translatePropertyToCpp(moduleName, prop, resolveAlias, enumMap),
          ),
        }),
      ];
    });

    const fileName = `${libraryName}JSI.h`;
    const replacedTemplate = FileTemplate({modules});

    return new Map([[fileName, replacedTemplate]]);
  },
};
